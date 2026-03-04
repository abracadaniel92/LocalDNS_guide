# CoreDNS + nginx: Local access to AXM on Windows

Access AXM services by hostname on the local network without internet, Cloudflare, or a public domain.

```
Browser (axm.local:8080)
   │
   ▼
CoreDNS (:53) resolves axm.local → 192.168.1.133
   │
   ▼
nginx (:8080) routes by Host header → backend
   │
   ├── axm.local        → Platform   (127.0.0.1:50000)
   ├── superadmin.local  → SuperAdmin (127.0.0.1:50001)
   └── vnhost.local      → VnHost    (127.0.0.1:50002)
```

---

## What each component does

| Component | Role | Listens on |
|-----------|------|------------|
| **CoreDNS** | DNS server. Resolves `axm.local`, `superadmin.local`, `vnhost.local` → server IP (`192.168.1.133`). Forwards everything else to public DNS (8.8.8.8). | UDP port **53** |
| **nginx** | Reverse proxy. Receives HTTP on port 8080, matches the `Host` header, and proxies to the correct AXM backend. Sends `Host: localhost` to backends so Kestrel accepts the request. | TCP port **8080** |
| **AXM backends** | Platform (50000), SuperAdmin (50001), VnHost (50002). Kestrel apps that only accept `Host: localhost` by default. nginx handles the translation. | TCP 50000, 50001, 50002 |

---

## File locations

### On the AXM server (suggested paths)

| File | Suggested path | Purpose |
|------|----------------|---------|
| **CoreDNS binary** | `C:\coredns\coredns.exe` | DNS server (~55 MB single binary) |
| **Corefile** | `C:\coredns\Corefile` | CoreDNS config: listen port, hosts file, upstream forwarder |
| **hosts.txt** | `C:\coredns\hosts.txt` | DNS records: hostname → IP mapping |
| **nginx.exe** | `C:\nginx\nginx.exe` | Reverse proxy |
| **nginx.conf** | `C:\nginx\conf\nginx.conf` | Main nginx config (includes axm.conf) |
| **axm.conf** | `C:\nginx\conf\axm.conf` | AXM server blocks: host-based routing |

### In the repo (source of truth)

| File | Repo path |
|------|-----------|
| **Corefile** | `lenovo-homelab/axm-windows/coredns/Corefile` |
| **hosts.txt** | `lenovo-homelab/axm-windows/coredns/hosts.txt` |
| **nginx.conf** | `lenovo-homelab/axm-windows/nginx/nginx.conf` |
| **axm.conf** | `lenovo-homelab/axm-windows/nginx/axm.conf` |

Copy the four config files from the repo to the server. Then edit `hosts.txt` and `axm.conf` to use the new server's IP (see "Customization" section below).

---

## Configuration files

### CoreDNS – Corefile

```
.:53 {
    hosts hosts.txt {
        fallthrough
    }
    forward . 8.8.8.8 8.8.4.4
    log
}
```

- Listens on **port 53** (standard DNS; requires Administrator).
- Resolves names from `hosts.txt`. If a name isn't in the file, forwards the query to Google DNS (8.8.8.8, 8.8.4.4).
- `fallthrough` means: if not found in hosts.txt, try the next plugin (forward).
- `log` prints queries to the console (useful for debugging).

### CoreDNS – hosts.txt

```
192.168.1.133 axm.local superadmin.local vnhost.local
```

One line per IP. All three hostnames resolve to the AXM server. Add more lines for additional services or change the IP if the server moves.

### nginx – nginx.conf

```nginx
worker_processes  1;
error_log  logs/error.log;
pid        logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    server_names_hash_bucket_size  64;
    map_hash_bucket_size 128;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;

    include axm.conf;
}
```

### nginx – axm.conf

```nginx
server {
    listen       8080;
    server_name  axm.local ~^axm\.local axm.gmojsoski.com;

    location / {
        proxy_pass http://127.0.0.1:50000;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

server {
    listen       8080;
    server_name  superadmin.local ~^superadmin\.local superadmin.gmojsoski.com;

    location / {
        proxy_pass http://127.0.0.1:50001;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

server {
    listen       8080;
    server_name  vnhost.local ~^vnhost\.local vnhost.gmojsoski.com;

    location / {
        proxy_pass https://127.0.0.1:50002;
        proxy_http_version 1.1;
        proxy_ssl_verify off;
        proxy_set_header Host localhost;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

# LAN access by IP → Platform
server {
    listen       8080;
    server_name  192.168.1.133;

    location / {
        proxy_pass http://127.0.0.1:50000;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

# Default server: proxy to Platform
server {
    listen       8080 default_server;
    server_name  _;

    location / {
        proxy_pass http://127.0.0.1:50000;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

**Key detail:** `proxy_set_header Host localhost` — Kestrel only accepts `localhost` as Host. nginx sends `localhost` to the backend and keeps the real hostname in `X-Forwarded-Host`.

---

## Setup from scratch

### Prerequisites

- Windows 10/11 or Windows Server
- AXM bundle running (Platform on 50000, SuperAdmin on 50001, VnHost on 50002)

### Step 0: Download and install nginx + CoreDNS

**nginx:**

1. Download the Windows zip from https://nginx.org/en/download.html (e.g. "Mainline version" or "Stable version" → Windows zip).
2. Extract to a folder, e.g. `C:\nginx\` (so you have `C:\nginx\nginx.exe`).
3. Copy `nginx.conf` and `axm.conf` from this repo (`lenovo-homelab/axm-windows/nginx/`) into `C:\nginx\conf\`.

**CoreDNS:**

1. Download the Windows binary from https://github.com/coredns/coredns/releases (look for `coredns_*_windows_amd64.tgz`).
2. Extract `coredns.exe` to a folder, e.g. `C:\coredns\`.
3. Copy `Corefile` and `hosts.txt` from this repo (`lenovo-homelab/axm-windows/coredns/`) into `C:\coredns\`.
4. **Edit `hosts.txt`**: change the IP (`192.168.1.133`) to the IP of this new machine.
5. **Edit `axm.conf`**: change `server_name 192.168.1.133` to the IP of this new machine.

### Step 1: Start CoreDNS (as Administrator)

1. Open **PowerShell as Administrator** (right-click → Run as administrator).
2. Navigate to the CoreDNS folder:
   ```powershell
   cd "C:\coredns"
   ```
3. Start CoreDNS:
   ```powershell
   .\coredns.exe -conf Corefile
   ```
4. You should see:
   ```
   .:53
   CoreDNS-1.11.1
   windows/amd64, go1.20.7, ae2bbc2
   ```
5. Leave this window open. CoreDNS runs in the foreground.

### Step 2: Start nginx

In a separate PowerShell (normal, no admin needed):

```powershell
cd "C:\nginx"
.\nginx.exe
```

Verify it's running:

```powershell
netstat -ano | findstr "8080"
```

You should see `LISTENING` on port 8080.

To test the config before starting:

```powershell
.\nginx.exe -t
```

### Step 3: Point client DNS to 127.0.0.1 (on the server)

On the AXM server itself:

1. **Win + R** → `ncpa.cpl` → Enter.
2. Right-click your active adapter (Ethernet or Wi-Fi) → **Properties**.
3. Select **Internet Protocol Version 4 (TCP/IPv4)** → **Properties**.
4. Choose **Use the following DNS server addresses**:
   - Preferred: **127.0.0.1**
   - Alternate: **8.8.8.8** (optional backup)
5. OK → OK.

### Step 4: Test DNS

```powershell
nslookup axm.local 127.0.0.1
nslookup superadmin.local 127.0.0.1
```

Both should return **192.168.1.133**.

### Step 5: Open in browser

- **http://axm.local:8080** → AXM Platform
- **http://superadmin.local:8080** → SuperAdmin
- **http://vnhost.local:8080** → VnHost

---

## Client devices (other PCs on the LAN)

For other devices to use the `.local` hostnames:

### Option A: Point their DNS to the AXM server

Set DNS on each device (or in the router's DHCP settings) to **192.168.1.133**. CoreDNS will resolve `.local` names and forward everything else to 8.8.8.8.

- **Windows:** `ncpa.cpl` → adapter → IPv4 → DNS = `192.168.1.133`
- **Mac:** System Preferences → Network → adapter → DNS = `192.168.1.133`
- **Linux:** Edit `/etc/resolv.conf` or NetworkManager: `nameserver 192.168.1.133`
- **Router (all devices):** In the router admin, set DHCP DNS server to `192.168.1.133`. All devices on the network will use CoreDNS automatically.

### Option B: Hosts file (per device, no CoreDNS needed)

On each device, add to the hosts file:

```
192.168.1.133   axm.local superadmin.local vnhost.local
```

- **Windows:** `C:\Windows\System32\drivers\etc\hosts` (edit as Administrator)
- **Mac/Linux:** `/etc/hosts` (edit as root)

### Option C: Phones / tablets

Phones can't edit hosts files easily. Use Option A (change DNS to 192.168.1.133) in the phone's Wi-Fi settings:

- **iPhone:** Settings → Wi-Fi → tap the (i) next to the network → Configure DNS → Manual → add `192.168.1.133`
- **Android:** Settings → Wi-Fi → long-press network → Modify → Advanced → IP settings → Static → DNS 1 = `192.168.1.133`

---

## Stopping the services

### Stop CoreDNS

Press **Ctrl+C** in the PowerShell window where CoreDNS is running.

### Stop nginx

```powershell
cd "C:\nginx"
.\nginx.exe -s quit
```

If that doesn't work (old processes), kill all nginx:

```powershell
taskkill /IM nginx.exe /F
```

**Important:** On Windows, `nginx -s reload` can leave old worker processes running with old config. If nginx behaves unexpectedly after a config change, always do a full stop (`taskkill /IM nginx.exe /F`) and restart (`.\nginx.exe`).

---

## Running as Windows services (production)

For always-on use, run both as Windows services so they start automatically.

### CoreDNS as a service

Use **NSSM** (Non-Sucking Service Manager):

1. Download NSSM from https://nssm.cc/download
2. Extract `nssm.exe` (use the `win64` version) to a folder in your PATH or the same folder as the service binary.
3. Install the service (run as Administrator):
   ```powershell
   nssm install CoreDNS "C:\coredns\coredns.exe" "-conf" "C:\coredns\Corefile"
   nssm set CoreDNS AppDirectory "C:\coredns"
   nssm start CoreDNS
   ```
4. Verify:
   ```powershell
   Get-Service CoreDNS
   nslookup axm.local 127.0.0.1
   ```

### nginx as a service

Same approach with NSSM (run as Administrator):

```powershell
nssm install nginx "C:\nginx\nginx.exe"
nssm set nginx AppDirectory "C:\nginx"
nssm start nginx
```

Verify:

```powershell
Get-Service nginx
netstat -ano | findstr "8080"
```

Or use the Windows Task Scheduler to run both at startup.

---

## Customization

### Change the server IP

If the AXM server gets a different IP (e.g. `192.168.1.200`):

1. Edit `hosts.txt`: change `192.168.1.133` → `192.168.1.200`
2. Edit `axm.conf`: change `server_name 192.168.1.133` → `server_name 192.168.1.200`
3. Restart CoreDNS (Ctrl+C, then re-run)
4. Restart nginx (`taskkill /IM nginx.exe /F` then `.\nginx.exe`)

### Add more hostnames

1. Add the hostname to `hosts.txt` (e.g. `192.168.1.133 newapp.local`)
2. Add a server block in `axm.conf` with the appropriate `proxy_pass`
3. Restart both services

### Use port 80 instead of 8080

Change `listen 8080` to `listen 80` in all server blocks in `axm.conf`. Then access via **http://axm.local** (no port needed). Port 80 may require running nginx as Administrator or as a service.

### Offline / air-gapped network

Remove the `forward . 8.8.8.8 8.8.4.4` line from the Corefile. CoreDNS will only answer for names in `hosts.txt` and return NXDOMAIN for everything else. No internet needed.

---

## Troubleshooting

| Problem | Check |
|---------|-------|
| **Browser: "This site can't be reached" / DNS_PROBE** | CoreDNS not running, or device DNS not pointing to 127.0.0.1 / 192.168.1.133. Run `nslookup axm.local 127.0.0.1` to test. |
| **Browser: "404 Not Found nginx"** | Old nginx process with old config. Kill all: `taskkill /IM nginx.exe /F`, restart: `.\nginx.exe`. |
| **Browser: blank page or CORS errors** | The AXM SPA's `environment.json` points to `https://...gmojsoski.com` for API calls. For fully offline use, update `environment.json` to use `http://axm.local:8080` etc. (see "Offline app config" below). |
| **nslookup works but browser doesn't** | Browser may use its own DNS (e.g. Chrome "Secure DNS"). Disable it: Chrome → Settings → Privacy → Security → Use secure DNS → Off. |
| **CoreDNS: "bind: permission denied"** | Port 53 requires Administrator. Run PowerShell as admin. |
| **CoreDNS: "bind: address already in use"** | Another DNS server (e.g. Windows DNS Client service) is using port 53. Stop the conflicting service or use a different port (e.g. `:5353` in Corefile, but clients must be configured for that port). |
| **nginx won't start** | Check `logs\error.log`. Common: port 8080 in use, missing config file, syntax error. Run `.\nginx.exe -t` to test config. |

### Offline app config (optional)

If the network has **no internet** and you want login/auth to work with `.local` hostnames:

1. **Platform** `environment.json` (`backend\axm.platform\wwwroot\environments\environment.json`):
   - `apiUrl` → `http://axm.local:8080`
   - `authApiUrl` → `http://superadmin.local:8080`

2. **SuperAdmin** `environment.json` (`backend\axm.superadmin\wwwroot\web\environments\environment.json`):
   - `apiUrl` → `http://superadmin.local:8080`
   - `authApiUrl` → `http://superadmin.local:8080`
   - `axManagerUrl` → `http://axm.local:8080`

3. **CORS / OpenID** in backend `appsettings.Development.json`:
   - Add `http://axm.local:8080` and `http://superadmin.local:8080` to AllowedOrigins and redirect URIs.

4. **data.json** (bundle root):
   - Add `.local:8080` URLs to `openIdApplications` redirectUris.

These changes are only needed for a fully offline / intranet-only deployment. If the server has internet and you're fine with auth going through Cloudflare, leave the `gmojsoski.com` URLs.

---

## Summary

| URL | Service | Backend |
|-----|---------|---------|
| **http://axm.local:8080** | AXM Platform | 127.0.0.1:50000 |
| **http://superadmin.local:8080** | SuperAdmin | 127.0.0.1:50001 |
| **http://vnhost.local:8080** | VnHost | 127.0.0.1:50002 |
| **http://192.168.1.133:8080** | AXM Platform (by IP) | 127.0.0.1:50000 |

**Stack:** CoreDNS (DNS) + nginx (reverse proxy) + AXM Kestrel backends. No internet, no Cloudflare, no public domain required.

---

## Quick start: replicate on a new machine

Checklist for setting up on a fresh Windows PC (e.g. at a client site).

1. **Get the server's LAN IP** (e.g. `ipconfig` → note the IPv4 address, say `10.0.0.50`).
2. **Download nginx** from https://nginx.org/en/download.html → extract to `C:\nginx\`.
3. **Download CoreDNS** from https://github.com/coredns/coredns/releases → extract `coredns.exe` to `C:\coredns\`.
4. **Copy configs from this repo:**
   - `lenovo-homelab/axm-windows/nginx/nginx.conf` → `C:\nginx\conf\nginx.conf`
   - `lenovo-homelab/axm-windows/nginx/axm.conf` → `C:\nginx\conf\axm.conf`
   - `lenovo-homelab/axm-windows/coredns/Corefile` → `C:\coredns\Corefile`
   - `lenovo-homelab/axm-windows/coredns/hosts.txt` → `C:\coredns\hosts.txt`
5. **Edit for new IP:**
   - `C:\coredns\hosts.txt`: replace `192.168.1.133` with `10.0.0.50`
   - `C:\nginx\conf\axm.conf`: replace `192.168.1.133` in `server_name` with `10.0.0.50`
6. **Install and start AXM bundle** (Platform on 50000, SuperAdmin on 50001, VnHost on 50002).
7. **Start CoreDNS** (Admin PowerShell): `cd C:\coredns; .\coredns.exe -conf Corefile`
8. **Start nginx** (normal PowerShell): `cd C:\nginx; .\nginx.exe`
9. **Set DNS on the server** to `127.0.0.1` (ncpa.cpl → adapter → IPv4 → DNS).
10. **Test:** `nslookup axm.local 127.0.0.1` → should return `10.0.0.50`.
11. **Open browser:** `http://axm.local:8080` → AXM Platform.
12. **Client devices:** set their DNS to `10.0.0.50` (or add hosts file entries).
13. **(Optional) Install as services** using NSSM (see "Running as Windows services" above).
14. **(Optional) Offline app config** — if no internet, update `environment.json` files (see "Offline app config" above).
