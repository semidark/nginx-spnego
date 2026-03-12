# nginx-spnego

NGINX with the **SPNEGO/Kerberos module** precompiled for GSSAPI-based Single Sign-On authentication, packaged as a Docker container acting as a **reverse proxy**. Designed for enterprise environments using **FreeIPA** or **Windows Server Active Directory**.

---

## 🐳 Quick Start

```bash
# 1. Copy and fill in environment variables
cp .env.example .env
$EDITOR .env

# 2. Place your Kerberos keytab
cp nginx.keytab keytab/nginx.keytab

# 3. Configure your reverse proxy site
$EDITOR config/sites-enabled/default

# 4. Start the container
docker compose up -d
```

---

## 🔧 Configuration

### Environment Variables

Copy [`.env.example`](.env.example) to `.env` and set the following variables:

| Variable | Required | Default | Description |
|---|---|---|---|
| `KRB5_REALM` | **Required** | — | Kerberos realm in uppercase. E.g. `CORP.EXAMPLE.COM` |
| `KRB5_KDC` | **Required** | — | KDC hostname (AD DC or FreeIPA server). E.g. `dc01.corp.example.com` |
| `KRB5_ADMIN_SERVER` | Optional | `KRB5_KDC` | Admin server hostname. Defaults to `KRB5_KDC`. |
| `KRB5_DOMAIN` | Optional | lowercase of `KRB5_REALM` | DNS domain for `domain_realm` mapping. E.g. `corp.example.com` |
| `SSL_HOSTNAME` | Optional | container hostname | Hostname for the self-signed TLS certificate fallback. |
| `KEYTAB_PATH` | Optional | `/etc/nginx/keytab/nginx.keytab` | Path to the keytab file inside the container. |
| `KEYTAB_WAIT_TIMEOUT` | Optional | `120` | Seconds to wait for the keytab file before failing. |
| `NGINX_LOG_LEVEL` | Optional | `warn` | NGINX error log level (`debug`, `info`, `notice`, `warn`, `error`, `crit`). |

### NGINX Site Configuration

The site configuration is mounted from [`config/sites-enabled/default`](config/sites-enabled/default) into the container at `/etc/nginx/sites-enabled/default`. Edit this file to configure your reverse proxy backend and any additional locations.

The example configuration includes:
- HTTP → HTTPS redirect on port 80
- SPNEGO/Kerberos authentication on port 443
- `proxy_pass` to a backend server with `X-Remote-User` header forwarding
- A `/health` endpoint on both port 80 and 443 (no auth required)

### 🔑 Kerberos Keytab

Place your keytab at `keytab/nginx.keytab`. It is mounted read-only into the container.

#### Creating a Service Principal and Keytab

**For FreeIPA:**

```bash
# Create the service principal
ipa service-add HTTP/proxy.corp.example.com

# Export the keytab
ipa-getkeytab -s ipa.corp.example.com \
  -p HTTP/proxy.corp.example.com@CORP.EXAMPLE.COM \
  -k keytab/nginx.keytab
```

**For Windows Server Active Directory:**

```cmd
# Create the SPN on the service account
setspn -A HTTP/proxy.corp.example.com nginx-svc

# Export the keytab (run on the DC)
ktpass -princ HTTP/proxy.corp.example.com@CORP.EXAMPLE.COM \
  -mapuser nginx-svc@CORP.EXAMPLE.COM \
  -pass <password> \
  -out nginx.keytab \
  -ptype KRB5_NT_PRINCIPAL \
  -crypto AES256-SHA1
```

### 🔐 TLS Certificates

On first startup, if no certificates are found in `certs/`, the entrypoint script **automatically generates a self-signed certificate** (valid 10 years) using `SSL_HOSTNAME`. A warning is logged.

To use **real certificates**, mount them into the container:

```yaml
# docker-compose.yaml
volumes:
  - ./certs/nginx.crt:/etc/nginx/ssl/nginx.crt:ro
  - ./certs/nginx.key:/etc/nginx/ssl/nginx.key:ro
```

The entrypoint detects mounted certificates (by checking if they are not owned by root) and skips self-signed generation.

To **regenerate** the self-signed certificate:

```bash
rm certs/nginx.crt certs/nginx.key
docker compose restart nginx-spnego
```

---

## 🏗️ Directory Structure

```
nginx-spnego/
├── .env.example              # Environment variable template
├── .gitignore
├── docker-compose.yaml       # Production Docker Compose
├── k8s.example.yaml          # Kubernetes deployment example
├── resolv.conf.example       # Custom DNS example
├── README.md
├── certs/                    # TLS certificates (auto-generated or mounted)
│   └── .gitkeep
├── config/                   # Runtime configuration (mounted into container)
│   ├── krb5.conf.example     # Kerberos config reference
│   ├── nginx.conf            # Main NGINX config
│   └── sites-enabled/
│       └── default           # Site config with reverse proxy + SPNEGO
├── keytab/                   # Kerberos keytab (mounted into container)
│   └── .gitkeep
└── src/                      # Docker build context
    ├── Dockerfile
    ├── entrypoint.sh
    └── krb5.conf.template    # Template for runtime krb5.conf generation
```

---

## 🔨 Building the Image

```bash
docker build -t your-registry/nginx-spnego:1.0.0 ./src
```

Update the `image:` field in [`docker-compose.yaml`](docker-compose.yaml) or [`k8s.example.yaml`](k8s.example.yaml) accordingly.

---

## 🩺 Health Check

The `/health` endpoint is available on both **port 80** and **port 443** without authentication:

```
GET /health → 200 OK
```

Used by the Docker `HEALTHCHECK` instruction and compatible with load balancer health probes.

---

## 🔑 AES Encryption

For Windows Active Directory environments, ensure the service account has AES encryption types configured:

- Set `msDS-SupportedEncryptionTypes=24` on the service account (AES128 + AES256)
- Perform a password reset after setting encryption types to regenerate Kerberos keys with AES
- Export the keytab with AES encryption types

**Verify AES encryption in the keytab:**

```bash
# Should show aes256-cts and aes128-cts entries
docker compose exec nginx-spnego klist -ke /etc/nginx/keytab/nginx.keytab
```

This ensures compatibility with modern Windows clients and browsers that prefer or require AES encryption.

---

## 🔐 TLS Certificate Management

### Self-Signed Certificates (Default)

On first start, if `certs/nginx.crt` and `certs/nginx.key` do not exist, the entrypoint generates them automatically. The hostname used is `SSL_HOSTNAME` (or the container hostname if not set). A warning is printed to the log.

Certificates are persisted in `certs/` and survive container restarts.

### Mounting Real Certificates

Place your certificate and key in `certs/` before starting:

```bash
cp /path/to/your.crt certs/nginx.crt
cp /path/to/your.key certs/nginx.key
docker compose up -d
```

### Importing Self-Signed Cert into Windows

To avoid browser warnings when using self-signed certificates:

**Via PowerShell (Admin):**

```powershell
# Import for current user
Import-Certificate -FilePath "C:\path\to\nginx.crt" -CertStoreLocation Cert:\CurrentUser\Root

# Import for all users (requires admin)
Import-Certificate -FilePath "C:\path\to\nginx.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

**Via GUI:** Open `certmgr.msc` → Trusted Root Certification Authorities → Certificates → Right-click → All Tasks → Import.

After importing, restart Edge and Chrome completely.

---

## 🌐 Browser Configuration for SPNEGO

Browsers must be configured to send Kerberos tickets automatically to the proxy host.

### Local Intranet Zone (Edge & Chrome on Windows)

1. Open `inetcpl.cpl` → **Security** tab → **Local intranet** → **Sites** → **Advanced**
2. Add `https://proxy.corp.example.com`
3. Restart the browser

### Chrome Policy (Enterprise or Testing)

**Via Registry (run as Administrator):**

```powershell
New-Item -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "AuthServerWhitelist" -Value "*.corp.example.com"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "AuthNegotiateDelegateWhitelist" -Value "*.corp.example.com"
```

**Via Command Line (testing only):**

```cmd
chrome.exe --auth-server-whitelist="*.corp.example.com" --auth-negotiate-delegate-whitelist="*.corp.example.com"
```

### Edge Policy (Enterprise)

```powershell
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AuthServerWhitelist" -Value "*.corp.example.com"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AuthNegotiateDelegateWhitelist" -Value "*.corp.example.com"
```

---

## ☸️ Kubernetes Deployment

See [`k8s.example.yaml`](k8s.example.yaml) for a complete example. The architecture uses:

- A **Deployment** running this image with the keytab mounted from a `Secret`
- A **ClusterIP Service** exposing the SPNEGO auth pod internally
- An **Ingress** on the protected application using `auth-url` and `auth-response-headers` annotations to delegate authentication to the SPNEGO service
- The authenticated username is forwarded to backends via the `X-Authenticated-User` header

Update the image reference in `k8s.example.yaml` to your own registry before deploying.

---

## 🔍 Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Container exits at startup | Keytab not found within `KEYTAB_WAIT_TIMEOUT` | Ensure `keytab/nginx.keytab` exists and is mounted correctly |
| `KRB5_REALM` or `KRB5_KDC` not set | Missing required env vars | Set them in `.env` |
| DNS resolution failures | Wrong DNS server | Mount a custom `resolv.conf` (see [`resolv.conf.example`](resolv.conf.example)) |
| Browser not sending Kerberos tickets | Site not in Local Intranet zone | See [Browser Configuration](#-browser-configuration-for-spnego) |
| Certificate warnings | Self-signed cert not trusted | Import `certs/nginx.crt` into the OS trust store |
| `kinit` fails | Wrong realm or KDC | Verify `KRB5_REALM` and `KRB5_KDC` match your environment |

**Check container logs:**

```bash
docker compose logs -f nginx-spnego
```

**Test NGINX config syntax:**

```bash
docker compose exec nginx-spnego nginx -t
```

---

## 🧪 Testing

```bash
# Obtain a Kerberos ticket
kinit username@CORP.EXAMPLE.COM

# Test SPNEGO authentication
curl -vv --negotiate -u : https://proxy.corp.example.com/

# Test health endpoint (no auth)
curl https://proxy.corp.example.com/health
```

If SPNEGO is working correctly, the server responds without prompting for credentials and the backend receives the `X-Remote-User` header with the authenticated username.
