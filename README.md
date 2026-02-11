# nginx-spnego

Docker image of **NGINX with SPNEGO (Kerberos) module** precompiled for GSSAPI-based authentication.  
This image is intended to be used in environments with [FreeIPA](https://www.freeipa.org/) or Windows Server for secure, enterprise-grade SSO authentication.


## 🐳 Usage

### 1. Create a  Service Principal for NGINX

#### 1.1 For FreeIPA

> Replace hostnames with your actual server FQDNs.

```bash
ipa service-add HTTP/test.example.com
```

#### 1.2 For Windows Server
> Replace hostnames with your actual server FQDNs.

```
setspn -A HTTP/test.example.com <user>
```
User must exist!

### 2. Generate a Keytab for the NGINX Host

#### 2.1 For FreeIPA server

```bash
ipa-getkeytab -s <freeipa-server> \
  -p HTTP/test.example.com@EXAMPLE.COM \
  -k nginx.keytab
```

#### 2.2 For Windows Server

```
ktpass -princ HTTP/test.example.com@<WINDOWS_DOMAIN> -mapuser <user>@<windows_domain> -pass <user_password> -out ./nginx.keytab -ptype KRB5_NT_PRINCIPAL -crypto RC4-HMAC-NT
```

### 3. Prepare Your NGINX Configuration

Place your SPNEGO-enabled NGINX site configuration file in `./default`. You can use default configuration as example

### 4. Run the Docker Container

```bash
docker run -it --rm \
  -v $(pwd)/default:/etc/nginx/sites-available/default \
  -v $(pwd)/nginx.keytab:/etc/nginx/nginx.keytab \
  --net=host \
  suprematic/nginx-spnego:latest
```

> Note: `--net=host` is used to allow NGINX to bind to system ports.

### 5. Test the Setup

From a Kerberos-authenticated client:

```bash
curl -vv --negotiate -u : http://test.example.com/
```
Depend on your system configuration, you should be authenticated before (for linux):
```bash
kinit <username>
```

If everything is configured correctly, the server should respond without prompting for credentials.

Some browsers may require additional configurations!
For example, MS Edge requires that site must be added into 'Local Intranet' list and available via HTTPS.

---

## 🔑 AES Encryption (Automated)

When used with the admockup domain controller, AES encryption is **automatically configured** for the SPNEGO service account:

- The DC sets `msDS-SupportedEncryptionTypes=24` (AES128 + AES256) on the service account
- A password reset is performed after setting encryption types to regenerate Kerberos keys with AES
- The keytab is exported with AES encryption types

This ensures compatibility with modern Windows clients and browsers that prefer or require AES encryption.

**Verify AES encryption is configured:**
```bash
# Check keytab encryption types (should show aes256-cts and aes128-cts)
docker exec auth-gateway klist -ke /etc/nginx/keytab/nginx.keytab

# Check user encryption attribute (should show 24)
docker exec dc samba-tool user show nginx-auth --attributes=msDS-SupportedEncryptionTypes
```

---

## 🔐 TLS Configuration

The auth-gateway automatically generates self-signed TLS certificates on first startup. This enables HTTPS, which is required for proper SPNEGO authentication in modern browsers (Edge, Chrome).

### How It Works

1. On first container start, if no certificates exist in `./nginx-spnego/certs/`, the entrypoint script generates:
   - `nginx.crt` - Self-signed certificate (valid for 10 years)
   - `nginx.key` - Private key

2. Certificates are persisted on the host filesystem, so they survive container restarts and rebuilds.

3. HTTP requests on port 80 are automatically redirected to HTTPS on port 443.

### Customizing the Certificate Hostname

Set the `SSL_HOSTNAME` environment variable in `docker-compose.yaml`:

```yaml
auth-gateway:
  environment:
    - SSL_HOSTNAME=myproxy.example.com
```

### Importing the Certificate into Windows 11

To avoid browser certificate warnings and enable seamless SPNEGO authentication in **both Edge and Chrome**, you need to import the certificate into the Windows Certificate Store. Both browsers use the same system store.

#### Method 1: Using Certificate Manager (GUI)

1. **Copy the certificate** (`./nginx-spnego/certs/nginx.crt`) to your Windows machine

2. **Open Certificate Manager:**
   - Press `Win + R`, type `certmgr.msc`, press Enter
   - Or: Search for "Manage user certificates" in the Start menu

3. **Import the certificate:**
   - In the left pane, expand **Trusted Root Certification Authorities**
   - Right-click on **Certificates** → **All Tasks** → **Import...**
   - Click **Next**
   - Click **Browse**, select your `nginx.crt` file
   - Click **Next**
   - Ensure "Place all certificates in the following store" shows **Trusted Root Certification Authorities**
   - Click **Next** → **Finish**
   - Click **Yes** when prompted about the security warning

#### Method 2: Double-Click Import

1. Copy `./nginx-spnego/certs/nginx.crt` to your Windows client
2. Double-click the `.crt` file
3. Click **Install Certificate...**
4. Select **Local Machine** (requires admin) or **Current User**
5. Click **Next**
6. Select **Place all certificates in the following store**
7. Click **Browse** → select **Trusted Root Certification Authorities**
8. Click **Next** → **Finish**

#### Method 3: PowerShell (Admin)

```powershell
# Import for current user only
Import-Certificate -FilePath "C:\path\to\nginx.crt" -CertStoreLocation Cert:\CurrentUser\Root

# Or import for all users on the machine (requires admin)
Import-Certificate -FilePath "C:\path\to\nginx.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

#### Verifying the Import

1. **Restart Edge and Chrome** (close all windows completely)
2. Navigate to `https://proxy.samdom.example.com/`
3. You should see a secure connection (padlock icon) without certificate warnings

#### Troubleshooting Chrome Certificate Errors

Chrome may cache certificate errors. If you still see warnings after importing:
- Clear browsing data: Navigate to `chrome://settings/clearBrowserData`
- Or restart Chrome completely: Navigate to `chrome://restart`

### Regenerating Certificates

To regenerate certificates (e.g., for a new hostname):

```bash
rm ./nginx-spnego/certs/nginx.crt ./nginx-spnego/certs/nginx.key
docker compose restart auth-gateway
```

### Browser Configuration for SPNEGO (Windows 11)

Even with TLS and a trusted certificate, browsers need to be configured to send Kerberos tickets automatically. Without this configuration, you may be prompted for credentials twice or SPNEGO won't work at all.

#### Adding Site to Local Intranet Zone (Edge & Chrome)

Both Edge and Chrome use Windows Internet Options for Intranet zone settings:

1. **Open Internet Options:**
   - Press `Win + R`, type `inetcpl.cpl`, press Enter
   - Or: Search for "Internet Options" in the Start menu

2. **Configure Local Intranet Zone:**
   - Go to the **Security** tab
   - Click on **Local intranet**
   - Click **Sites** button
   - Click **Advanced** button
   - In "Add this website to the zone", enter: `https://proxy.samdom.example.com`
   - Click **Add**
   - Click **Close** → **OK** → **OK**

3. **Restart your browser** for changes to take effect

#### Chrome: Alternative Configuration via Policy

For enterprise deployments or if Internet Options doesn't work, use Chrome policies:

**Via Registry (Windows):**
```powershell
# Run as Administrator
New-Item -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "AuthServerWhitelist" -Value "*.samdom.example.com"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "AuthNegotiateDelegateWhitelist" -Value "*.samdom.example.com"
```

**Via Command Line (for testing):**
```cmd
chrome.exe --auth-server-whitelist="*.samdom.example.com" --auth-negotiate-delegate-whitelist="*.samdom.example.com"
```

#### Edge: Alternative Configuration via Policy

**Via Registry (Windows):**
```powershell
# Run as Administrator
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AuthServerWhitelist" -Value "*.samdom.example.com"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AuthNegotiateDelegateWhitelist" -Value "*.samdom.example.com"
```

#### Verifying SPNEGO is Working

After configuration, navigate to `https://proxy.samdom.example.com/`. You should:
- See no certificate warnings (if certificate is imported)
- Be authenticated automatically without any credential prompts
- See your Kerberos username displayed on the page

---

Here's a `README.md` description for your SPNEGO-based authentication project to protect internal Kubernetes HTTP applications. It explains the architecture, purpose, and how to use it:

---

## Usage in Kubernetes

### 🔒 Use Case

This solution is ideal for internal web applications deployed in a Kubernetes cluster where centralized authentication via **FreeIPA**, **Active Directory**, or another Kerberos-compatible realm is required. It integrates seamlessly with an Ingress controller and supports secure header-based identity propagation.

---

### 🧩 Architecture Overview

* **NGINX + SPNEGO**: Runs as a standalone deployment behind an internal service.
* **Ingress Auth Integration**: The Ingress controller delegates authentication to the SPNEGO service using the `auth-url` and `auth-response-headers` annotations.
* **Kerberos Keytab**: Provided securely via Kubernetes Secret.
* **User Identity**: Passed to backend applications via the `X-Authenticated-User` HTTP header.

---

### 🚀 Components

#### 1. `ConfigMap`: NGINX Configuration

Defines the NGINX server block, enabling SPNEGO authentication via the `auth_gss` directive. The user identity is exposed with the `X-Authenticated-User` header.

#### 2. `Secret`: Kerberos Keytab

Contains the keytab file (`http-headers.keytab`) for the SPNEGO service principal (e.g., `HTTP/spnego-auth.default.svc.cluster.local@YOUR.REALM`), base64-encoded.

#### 3. `Deployment`: SPNEGO Auth Service

Runs the custom NGINX image (`suprematic/nginx-spnego`) with:

* Mounted keytab at `/etc/nginx/keytab/nginx.keytab`
* Mounted `nginx.conf` from the ConfigMap
* Logs to `stdout` and `stderr` for easy access

#### 4. `Service`: Internal Access

A ClusterIP service exposes the NGINX pod at port 80.

#### 5. `Ingress`: Authentication Gateway

Ingress configuration for the protected application. Uses `auth-url` to delegate requests to the SPNEGO service and propagates the `X-Authenticated-User` header to the backend.
