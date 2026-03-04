# AXM on Windows – IIS Reverse Proxy + Cloudflare Tunnel

This folder contains configuration to expose AXM (Platform, SuperAdmin, VnHost) on **app.axm.gmojsoski.com**, **admin.axm.gmojsoski.com**, and **vnhost.axm.gmojsoski.com** using IIS as reverse proxy and Cloudflare Tunnel for HTTPS and internet access. Same hostnames work on LAN (via hosts or DNS) and from the internet (via tunnel).

## Architecture

| Frontend URL | Backend (this PC) |
|--------------|-------------------|
| https://app.axm.gmojsoski.com | Platform SPA & API → https://localhost:50000 |
| https://admin.axm.gmojsoski.com | SuperAdmin SPA & API → https://localhost:50001 |
| https://vnhost.axm.gmojsoski.com | VnHost → https://localhost:50002 |

- **IIS** terminates the request (HTTP on port 80), routes by `Host` header, and forwards to the AXM backends with `X-Forwarded-*` headers.
- **Cloudflare Tunnel** (cloudflared on this PC) sends traffic from Cloudflare to `http://localhost:80` (IIS). SSL is at Cloudflare; no IIS certificate needed for the tunnel path.
- **LAN**: Use hosts file or local DNS so the three hostnames resolve to this PC’s IP; clients hit IIS on port 80 (or 443 if you add HTTPS bindings and a cert).

## Prerequisites

### 1. Windows / IIS

- **Web Server (IIS)** with:
  - **WebSocket Protocol**
  - **URL Rewrite** (install before ARR)
  - **Application Request Routing (ARR)**
- **Enable ARR proxy**: IIS Manager → server node → Application Request Routing Cache → Server Proxy Settings → **Enable proxy**.
- **Optional**: At server level, disable “Reverse rewrite host in response headers” so response headers keep the external hostnames.

### 2. Backend ports

Confirm AXM is listening on this machine:

- Platform: **https://localhost:50000**
- SuperAdmin: **https://localhost:50001**
- VnHost: **https://localhost:50002**

Adjust `web.config` if your ports differ.

---

## Step 1: IIS site and web.config

1. Create a new site (e.g. **AXM Demo**).
2. Set physical path (e.g. `C:\inetpub\axm-demo`).
3. Copy **web.config** from this folder into the site’s physical path (root).
4. Add **HTTP** binding:
   - Type: **http**
   - Port: **80**
   - Host name: leave blank (or add later for multiple sites).
5. If you want LAN clients to use HTTPS directly (without Cloudflare), add **HTTPS** bindings and a cert (e.g. wildcard `*.axm.gmojsoski.com`). For tunnel-only access, HTTP on 80 is enough.

### Allowed server variables

`web.config` already declares `allowedServerVariables` for `HTTP_X_FORWARDED_HOST`, `HTTP_X_FORWARDED_PROTO`, and `HTTP_X_FORWARDED_FOR`. If your IIS version requires it, also add these in IIS Manager: site → URL Rewrite → View Server Variables → Add the same three names.

---

## Step 2: Local DNS / LAN access

So that **app.axm.gmojsoski.com**, **admin.axm.gmojsoski.com**, and **vnhost.axm.gmojsoski.com** resolve to this machine:

- **On this PC**: Edit `%SystemRoot%\System32\drivers\etc\hosts` (as Administrator). Use the lines in **hosts-snippet.txt**. Use `127.0.0.1` for local testing, or this PC’s LAN IP (e.g. `192.168.1.100`) if you want other devices to reach IIS on this machine.
- **On other LAN devices**: Either add the same lines to their hosts file (with this PC’s LAN IP), or point your router/local DNS so those three hostnames resolve to this PC’s IP.

Then open:

- https://app.axm.gmojsoski.com (or http if you only have HTTP binding)
- https://admin.axm.gmojsoski.com
- https://vnhost.axm.gmojsoski.com

If you use only HTTP on IIS, use **http** in the browser for LAN; from the internet you’ll use **https** via Cloudflare.

---

## Step 3: Cloudflare Tunnel (internet access)

1. **Install cloudflared** on this Windows PC (e.g. [Cloudflare Zero Trust docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/)).
2. **Create a tunnel** in the Zero Trust dashboard (or reuse an existing tunnel that runs on this machine). Download the credential JSON and place it in e.g. `%USERPROFILE%\.cloudflared\`.
3. **Config**: Create (or edit) `%USERPROFILE%\.cloudflared\config.yml`. Use the ingress block from **cloudflare-ingress-axm.yml** in this folder:
   - `app.axm.gmojsoski.com` → `http://localhost:80`
   - `admin.axm.gmojsoski.com` → `http://localhost:80`
   - `vnhost.axm.gmojsoski.com` → `http://localhost:80`
   If your tunnel config already has other hostnames, add these three and keep the catch-all `service: http_status:404` last.
4. **DNS**: In Cloudflare (zone gmojsoski.com), add CNAME records:
   - `app.axm` → `<tunnel-id>.cfargotunnel.com`
   - `admin.axm` → `<tunnel-id>.cfargotunnel.com`
   - `vnhost.axm` → `<tunnel-id>.cfargotunnel.com`
5. **Run tunnel**:  
   `cloudflared tunnel --config %USERPROFILE%\.cloudflared\config.yml run`  
   Or install and run as a Windows service.

After this, the same three URLs work from the internet over HTTPS via Cloudflare.

---

## Step 4: CORS and OpenID Connect

As in the AXM Manual Configuration:

- **CORS** `AllowedOrigins` in the AXM backends must use the public hostnames:
  - https://app.axm.gmojsoski.com
  - https://admin.axm.gmojsoski.com
- **OpenID Connect**: Authority, redirect URIs, and post-logout URIs must use **app.axm.gmojsoski.com** and **admin.axm.gmojsoski.com** (not localhost), so all redirects and token flows use the external hostnames.

---

## Files in this folder

| File | Purpose |
|------|--------|
| **web.config** | IIS URL Rewrite rules (host-based routing + forwarded headers + WebSocket). |
| **cloudflare-ingress-axm.yml** | Ingress snippet for Cloudflare Tunnel config. |
| **hosts-snippet.txt** | Example hosts entries for LAN/local testing. |
| **README.md** | This file. |

---

## Summary

- **IIS** reverse-proxies **app** / **admin** / **vnhost**.axm.gmojsoski.com to localhost 50000 / 50001 / 50002 with `X-Forwarded-*` and WebSockets.
- **Local DNS / hosts**: Point the three hostnames to this PC for LAN.
- **Cloudflare Tunnel**: Expose the same hostnames to the internet; tunnel targets `http://localhost:80` (IIS).
- **CORS and OIDC**: Use **https://app.axm.gmojsoski.com** and **https://admin.axm.gmojsoski.com** in AXM and identity provider config.
