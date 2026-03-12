#!/bin/sh
#
# Entrypoint script for nginx-spnego auth-gateway
#
# Responsibilities:
#   1. Validate required environment variables
#   2. Generate /etc/krb5.conf from template using envsubst
#   3. Handle TLS certificates (use mounted certs or generate self-signed)
#   4. Wait for Kerberos keytab to become available
#   5. Write nginx log level configuration snippet
#   6. Start NGINX
#

set -e

# -----------------------
# Required environment variables
# -----------------------
if [ -z "${KRB5_REALM}" ]; then
    echo "ERROR: KRB5_REALM environment variable is required."
    echo "       Example: KRB5_REALM=CORP.EXAMPLE.COM"
    exit 1
fi

if [ -z "${KRB5_KDC}" ]; then
    echo "ERROR: KRB5_KDC environment variable is required."
    echo "       Example: KRB5_KDC=dc01.corp.example.com"
    exit 1
fi

# -----------------------
# Derive defaults for optional variables
# -----------------------
KRB5_ADMIN_SERVER="${KRB5_ADMIN_SERVER:-${KRB5_KDC}}"
KRB5_DOMAIN="${KRB5_DOMAIN:-$(echo "${KRB5_REALM}" | tr '[:upper:]' '[:lower:]')}"
SSL_HOSTNAME="${SSL_HOSTNAME:-$(hostname)}"
KEYTAB_PATH="${KEYTAB_PATH:-/etc/nginx/keytab/nginx.keytab}"
KEYTAB_WAIT_TIMEOUT="${KEYTAB_WAIT_TIMEOUT:-120}"
KEYTAB_WAIT_INTERVAL=2
NGINX_LOG_LEVEL="${NGINX_LOG_LEVEL:-warn}"

CERT_DIR="/etc/nginx/ssl"
CERT_FILE="${CERT_DIR}/nginx.crt"
KEY_FILE="${CERT_DIR}/nginx.key"

echo "=== nginx-spnego startup ==="
echo "  KRB5_REALM:        ${KRB5_REALM}"
echo "  KRB5_KDC:          ${KRB5_KDC}"
echo "  KRB5_ADMIN_SERVER: ${KRB5_ADMIN_SERVER}"
echo "  KRB5_DOMAIN:       ${KRB5_DOMAIN}"
echo "  SSL_HOSTNAME:      ${SSL_HOSTNAME}"
echo "  KEYTAB_PATH:       ${KEYTAB_PATH}"
echo "  NGINX_LOG_LEVEL:   ${NGINX_LOG_LEVEL}"

# -----------------------
# Generate /etc/krb5.conf from template
# -----------------------
echo ""
echo "Generating /etc/krb5.conf from template..."
export KRB5_REALM KRB5_KDC KRB5_ADMIN_SERVER KRB5_DOMAIN
envsubst < /etc/nginx/templates/krb5.conf.template > /etc/krb5.conf
echo "  /etc/krb5.conf written."

# -----------------------
# TLS certificate handling
# -----------------------
echo ""
mkdir -p "${CERT_DIR}"

if [ -s "${CERT_FILE}" ] && [ -s "${KEY_FILE}" ]; then
    echo "Using mounted TLS certificates:"
    echo "  Certificate: ${CERT_FILE}"
    echo "  Private Key: ${KEY_FILE}"
else
    echo "WARNING: No mounted TLS certificates found at ${CERT_FILE} / ${KEY_FILE}."
    echo "WARNING: Generating self-signed certificate for ${SSL_HOSTNAME}."
    echo "WARNING: Self-signed certificates are NOT suitable for production use."
    echo "         Mount real certificates via volume to suppress this warning."
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "${KEY_FILE}" \
        -out "${CERT_FILE}" \
        -subj "/CN=${SSL_HOSTNAME}" \
        -addext "subjectAltName=DNS:${SSL_HOSTNAME},DNS:localhost,IP:127.0.0.1"
    chmod 644 "${CERT_FILE}"
    chmod 600 "${KEY_FILE}"
    echo "  Self-signed certificate generated:"
    echo "    Certificate: ${CERT_FILE}"
    echo "    Private Key: ${KEY_FILE}"
fi

# -----------------------
# Wait for keytab to be available
# -----------------------
echo ""
echo "Waiting for keytab at ${KEYTAB_PATH}..."
elapsed=0
while [ ! -f "${KEYTAB_PATH}" ]; do
    sleep "${KEYTAB_WAIT_INTERVAL}"
    elapsed=$((elapsed + KEYTAB_WAIT_INTERVAL))
    if [ "${elapsed}" -ge "${KEYTAB_WAIT_TIMEOUT}" ]; then
        echo "ERROR: Keytab not found after ${KEYTAB_WAIT_TIMEOUT}s at ${KEYTAB_PATH}"
        echo "       The domain controller should generate the keytab automatically."
        echo "       Check DC logs: docker compose logs domain-controller | grep SPNEGO"
        exit 1
    fi
    echo "  Still waiting for keytab... (${elapsed}s / ${KEYTAB_WAIT_TIMEOUT}s)"
done

echo "Keytab found at ${KEYTAB_PATH}"

# Verify keytab contents if klist is available
if command -v klist >/dev/null 2>&1; then
    echo "Keytab contents:"
    klist -kte "${KEYTAB_PATH}" 2>&1 | while read -r line; do
        echo "  ${line}"
    done
else
    echo "WARN: klist not available, cannot verify keytab contents"
fi

# -----------------------
# Write nginx log level configuration snippet
# -----------------------
echo ""
echo "Setting nginx error log level to: ${NGINX_LOG_LEVEL}"
mkdir -p /etc/nginx/conf.d
echo "error_log /var/log/nginx/error.log ${NGINX_LOG_LEVEL};" > /etc/nginx/conf.d/log-level.conf

# -----------------------
# Start nginx
# -----------------------
echo ""
echo "Starting NGINX with SPNEGO authentication..."
exec /usr/sbin/nginx -g "daemon off;"
