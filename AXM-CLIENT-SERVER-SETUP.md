# AXM Client-Server Environment Setup Guide

Comprehensive guide for deploying AXM (Platform, SuperAdmin, VnHost, CommNode) on a Windows server and making it accessible to LAN clients by hostname through a reverse proxy. Written for SimonsVoss engineers deploying at client sites and for client IT administrators.

---

## Table of contents

1. [Overview and architecture](#1-overview-and-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Choosing hostnames](#3-choosing-hostnames)
4. [DNS configuration](#4-dns-configuration)
5. [Reverse proxy setup](#5-reverse-proxy-setup)
6. [AXM bundle configuration for proxy access](#6-axm-bundle-configuration-for-proxy-access)
7. [Windows Firewall](#7-windows-firewall)
8. [Starting the services](#8-starting-the-services)
9. [Client device setup](#9-client-device-setup)
10. [Verification and testing](#10-verification-and-testing)
11. [Troubleshooting](#11-troubleshooting)
12. [Running as Windows services](#12-running-as-windows-services)
13. [Summary checklist](#13-summary-checklist)

---

## 1. Overview and architecture

### What this guide covers

AXM runs several backend applications on a single Windows PC (the "server"). Each application listens on its own port (e.g. 50000, 50001). Accessing `http://serverip:50000` works locally, but is not practical for end users or multiple client devices.

This guide sets up:

- **DNS** so that friendly hostnames (e.g. `axm.DOMAIN`, `superadmin.DOMAIN`) resolve to the server.
- **A reverse proxy** that listens on one port (e.g. 8080) and routes requests by hostname to the correct backend.
- **AXM configuration** so that login, CORS, and redirect flows work through the proxy.

After setup, users open `http://axm.DOMAIN:PROXY_PORT` in a browser and everything works transparently.

### Architecture

```
Client browser
    |
    |  http://axm.DOMAIN:8080
    v
[DNS resolution]  axm.DOMAIN --> SERVER_IP
    |
    v
[Reverse proxy on SERVER_IP:8080]
    |  Routes by Host header:
    |    axm.DOMAIN        --> http://127.0.0.1:50000   (Platform)
    |    superadmin.DOMAIN  --> http://127.0.0.1:50001   (SuperAdmin)
    |    vnhost.DOMAIN      --> http://127.0.0.1:50002   (VnHost)
    |    commnode.DOMAIN     --> http://127.0.0.1:COMMNODE_PORT (CommNode)
    v
[AXM backend applications on localhost]
```

### Standard port mapping

Ports are defined in `data.json` at the root of the AXM bundle. Check this file for actual values; they may differ per installation.

| Application | Default port | Hostname (example) |
|-------------|-------------|-------------------|
| **Platform** | 50000 | `axm.DOMAIN` |
| **SuperAdmin** | 50001 | `superadmin.DOMAIN` |
| **VnHost** | 50002 | `vnhost.DOMAIN` |
| **CommNode** | varies (check `data.json`) | `commnode.DOMAIN` |

> **Throughout this guide**, replace `DOMAIN` with your chosen domain suffix (e.g. `local`, `lan`, `company.com`), `SERVER_IP` with the server's LAN IPv4 address, and `PROXY_PORT` with the port the proxy listens on (e.g. `8080`). Replace backend ports if yours differ from the defaults above.

### Component roles

| Component | Role |
|-----------|------|
| **DNS** | Resolves hostnames to the server IP. Can be a hosts file, a local DNS server (CoreDNS), Active Directory DNS, router DNS, or any other DNS solution. |
| **Reverse proxy** | Accepts HTTP on one port, inspects the `Host` header, and forwards to the correct backend. Can be nginx, IIS with ARR, Apache, Caddy, Traefik, or any HTTP proxy. |
| **AXM backends** | The actual applications (Kestrel/.NET). Each listens on `localhost` on its own port. They are not exposed directly to the network; the proxy handles external access. |

---

## 2. Prerequisites

Before starting, ensure the following:

- **Windows 10/11 or Windows Server** on the machine that will run AXM.
- **AXM bundle** installed. You should have a folder containing `data.json` and a `backend/` directory with the application folders.
- **Administrator access** on the server (needed for DNS on port 53, firewall rules, and hosts file edits).
- **Static or reserved LAN IP** on the server. If the server gets its IP via DHCP, create a **DHCP reservation** in the router/DHCP server so the IP does not change. DNS entries and client hosts files depend on a stable IP.
- **Chosen hostnames** for each application (see section 3).
- **A reverse proxy** installed (nginx, IIS with ARR, or another proxy of your choice).
- **Ports confirmed**: open `data.json` and note the port for each application. The guide uses `50000`, `50001`, `50002` as examples.

---

## 3. Choosing hostnames

Each AXM application gets its own hostname. All hostnames point to the same server IP; the reverse proxy uses the `Host` header to route to the correct backend.

### Naming conventions

| Style | Example | When to use |
|-------|---------|-------------|
| `.local` suffix | `axm.local`, `superadmin.local`, `vnhost.local` | Quick demos, isolated labs. Note: `.local` may conflict with mDNS/Bonjour on some networks. |
| `.lan` suffix | `axm.lan`, `superadmin.lan`, `vnhost.lan` | Internal networks. `.lan` is not a reserved TLD, so it avoids mDNS conflicts. |
| Subdomain of a real domain | `axm.company.com`, `superadmin.company.com` | Production environments where DNS is centrally managed (e.g. Active Directory). |
| `.internal` suffix | `axm.internal`, `superadmin.internal` | RFC-reserved for private use; safe from public DNS collisions. |

### Rules

1. **One hostname per application.** Platform, SuperAdmin, VnHost (and CommNode if used) each need a distinct hostname.
2. **All hostnames resolve to the same server IP.** The proxy distinguishes them by the `Host` header, not by IP.
3. **Pick a proxy port** (e.g. `8080`). All hostnames share this port. Avoid port 80 if another service (e.g. IIS, Apache, or the Windows HTTP.sys driver) already uses it.
4. **Be consistent.** Use the same hostnames everywhere: DNS, proxy config, AXM config files, browser URLs.

For the rest of this guide, the placeholders `axm.DOMAIN`, `superadmin.DOMAIN`, `vnhost.DOMAIN`, and `commnode.DOMAIN` are used. Replace `DOMAIN` with whatever you chose.

---

## 4. DNS configuration

Clients must be able to resolve your chosen hostnames to `SERVER_IP`. There are three common approaches; choose the one that fits the environment.

### Comparison

| Option | Scope | Effort | Best for |
|--------|-------|--------|----------|
| **A. Hosts file** | Per device | Low (edit one file per device) | Quick demos, 1-3 client devices |
| **B. CoreDNS** | All devices that point DNS to the server | Medium (run a lightweight DNS server) | Environments without existing DNS infrastructure |
| **C. Client's own DNS** | Network-wide (automatic) | Low-Medium (add A records) | Environments with Active Directory, router DNS, Pi-hole, etc. |

---

### Option A: Hosts file (per device)

Edit the hosts file on **each device** (including the server itself) that needs to access AXM.

**Windows** (run Notepad as Administrator):

1. Open `C:\Windows\System32\drivers\etc\hosts` (set file filter to "All Files").
2. Add one line at the end:
   ```
   SERVER_IP    axm.DOMAIN superadmin.DOMAIN vnhost.DOMAIN commnode.DOMAIN
   ```
   Example: `192.168.1.100    axm.lan superadmin.lan vnhost.lan commnode.lan`
3. Save and close.

**Mac / Linux** (run as root or with sudo):

```bash
sudo nano /etc/hosts
```

Add the same line, save.

**Verify:**

```
ping axm.DOMAIN
```

Should show `SERVER_IP`.

---

### Option B: CoreDNS (lightweight DNS server on the AXM PC)

CoreDNS is a single-binary DNS server. It runs on the AXM server and resolves your hostnames; everything else is forwarded to public DNS (e.g. 8.8.8.8).

**1. Download CoreDNS**

- https://github.com/coredns/coredns/releases
- Get the `windows_amd64` archive. Extract `coredns.exe` to a folder, e.g. `C:\coredns\`.

**2. Create `Corefile`** in `C:\coredns\`:

```
.:53 {
    hosts hosts.txt {
        fallthrough
    }
    forward . 8.8.8.8 8.8.4.4
    log
}
```

**3. Create `hosts.txt`** in `C:\coredns\`:

```
SERVER_IP axm.DOMAIN superadmin.DOMAIN vnhost.DOMAIN commnode.DOMAIN
```

Replace `SERVER_IP` and the hostnames with your actual values.

**4. Start CoreDNS** (Administrator PowerShell):

```powershell
cd C:\coredns
.\coredns.exe -conf Corefile
```

Port 53 requires Administrator. Leave the window open (or install as a service; see section 12).

**5. Point clients to the server's DNS**

On each device (or in the router's DHCP settings), set DNS to `SERVER_IP`. Then all hostnames resolve via CoreDNS.

- **On the server itself:** set DNS to `127.0.0.1` (ncpa.cpl -> adapter -> IPv4 -> DNS).
- **On other devices:** set DNS to `SERVER_IP`.
- **Network-wide:** set the DHCP DNS option in the router to `SERVER_IP`.

**Verify:**

```
nslookup axm.DOMAIN 127.0.0.1
```

Should return `SERVER_IP`.

---

### Option C: Client's own DNS infrastructure

If the environment already has DNS (Active Directory, Windows Server DNS, router DNS, Pi-hole, Unbound, etc.), add A records for each hostname pointing to `SERVER_IP`.

**Active Directory DNS (Windows Server):**

1. Open DNS Manager (`dnsmgmt.msc`).
2. In the appropriate forward lookup zone, create **A records**:
   - `axm` -> `SERVER_IP`
   - `superadmin` -> `SERVER_IP`
   - `vnhost` -> `SERVER_IP`
   - `commnode` -> `SERVER_IP`
3. Clients joined to the domain will resolve these automatically.

**Router DNS:**

Most routers allow adding static DNS entries in the admin UI. Add the same hostname -> IP mappings. All devices using the router for DNS will resolve them.

**Pi-hole / Unbound / dnsmasq:**

Add local DNS records or custom entries mapping each hostname to `SERVER_IP`. Consult the specific tool's documentation.

**General rule:** Create one **A record** per hostname, all pointing to the same `SERVER_IP`.

---

## 5. Reverse proxy setup

### What the proxy does

The proxy listens on a single port (e.g. 8080) on `0.0.0.0` (all interfaces). When a request arrives, it inspects the `Host` header and forwards the request to the correct AXM backend on `127.0.0.1`.

### Key requirements (any proxy)

Regardless of which proxy software you use, it must:

1. **Listen on a LAN-accessible port** (e.g. 8080). Binding to `0.0.0.0` ensures it accepts connections from other devices, not just localhost.

2. **Route by Host header.** Each hostname maps to a different backend port:

   | Incoming Host header | Forward to |
   |---------------------|------------|
   | `axm.DOMAIN` | `http://127.0.0.1:50000` |
   | `superadmin.DOMAIN` | `http://127.0.0.1:50001` |
   | `vnhost.DOMAIN` | `http://127.0.0.1:50002` |
   | `commnode.DOMAIN` | `http://127.0.0.1:COMMNODE_PORT` |

3. **Forward headers** so the backend knows the original client request:

   | Header | Value | Purpose |
   |--------|-------|---------|
   | `X-Forwarded-Host` | Original host and port (e.g. `axm.DOMAIN:8080`) | Backend uses this for redirect URLs, CORS, and OIDC |
   | `X-Forwarded-Proto` | `http` or `https` | Backend knows the client's protocol |
   | `X-Forwarded-For` | Client IP address | Logging and access control |
   | `Host` | Original host and port (e.g. `axm.DOMAIN:8080`) | Kestrel/ASP.NET uses this for URL generation. Alternatively, send `Host: localhost` and rely on `X-Forwarded-Host` if the backend is configured for forwarded headers. |

4. **WebSocket support.** AXM uses SignalR (WebSockets). The proxy must forward `Upgrade` and `Connection` headers and use HTTP/1.1 for the upstream connection.

5. **Timeouts.** WebSocket connections are long-lived. Set a high read/proxy timeout (e.g. 86400 seconds / 24 hours).

---

### nginx example

This repo includes ready-to-use nginx configs in the `nginx/` folder.

**`nginx.conf`** (main config):

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

**`axm.conf`** (one server block per hostname):

```nginx
server {
    listen       8080;
    server_name  axm.DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:50000;
        proxy_http_version 1.1;
        proxy_set_header Host $host:$server_port;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host:$server_port;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

server {
    listen       8080;
    server_name  superadmin.DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:50001;
        # ... same headers as above ...
    }
}

server {
    listen       8080;
    server_name  vnhost.DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:50002;
        # ... same headers as above ...
    }
}

# Repeat for commnode.DOMAIN if used.
# Add a default_server block that proxies to Platform as a fallback.
```

**Setup steps:**

1. Download nginx for Windows from https://nginx.org/en/download.html.
2. Extract to e.g. `C:\nginx\`.
3. Replace `C:\nginx\conf\nginx.conf` with the config above.
4. Create `C:\nginx\conf\axm.conf` with the server blocks above (replace `DOMAIN` and ports).
5. Test: `.\nginx.exe -t` (should say "syntax is ok").
6. Start: `.\nginx.exe`.

---

### IIS example (URL Rewrite + ARR)

IIS uses **URL Rewrite** and **Application Request Routing (ARR)** for reverse proxying. The equivalent of the nginx forwarded headers are **IIS Server Variables**:

| nginx header | IIS Server Variable | Value |
|-------------|---------------------|-------|
| `X-Forwarded-Host` | `HTTP_X_FORWARDED_HOST` | `{HTTP_HOST}` |
| `X-Forwarded-Proto` | `HTTP_X_FORWARDED_PROTO` | `https` (or `http`) |
| `X-Forwarded-For` | `HTTP_X_FORWARDED_FOR` | `{REMOTE_ADDR}` |

**Setup overview:**

1. Install IIS with **WebSocket Protocol**, **URL Rewrite** (install before ARR), and **ARR**.
2. Enable ARR proxy: IIS Manager -> server node -> Application Request Routing Cache -> Server Proxy Settings -> Enable proxy.
3. Create a site (e.g. "AXM") with an HTTP binding on your chosen port.
4. Add URL Rewrite rules that match by `{HTTP_HOST}` and rewrite to the backend URLs.
5. In each rule's **Server Variables**, set the three `HTTP_X_FORWARDED_*` variables.
6. Optionally disable "Reverse rewrite host in response headers" at server level.

See `IIS-DOC-CHECKLIST.md` in this repo for a detailed comparison with the official AXM IIS documentation.

---

### Other proxies (Apache, Caddy, Traefik)

The same principles apply to any HTTP reverse proxy:

- **Apache:** Use `mod_proxy` with `ProxyPass` and `ProxyPassReverse`. Set `RequestHeader` for forwarded headers. Enable `mod_proxy_wstunnel` for WebSockets.
- **Caddy:** Use `reverse_proxy` directive with `header_up` for forwarded headers. WebSocket support is automatic.
- **Traefik:** Define routers with `Host()` rules and services pointing to the backend ports. Forwarded headers are handled automatically.

The key is always the same: route by `Host`, forward headers, support WebSockets.

---

## 6. AXM bundle configuration for proxy access

The AXM bundle must be told about the proxy URLs so that login redirects, CORS, and API calls work when accessed through the proxy. All paths below are relative to the **bundle root** (the folder containing `data.json`).

### 6.1 data.json (OpenID redirect URIs)

**File:** `data.json`
**Section:** `openIdApplications`

Add the proxy URLs to `redirectUris` so login/redirect flows accept them:

```json
"axm.webapp": {
    "redirectUris": [
        "http://localhost:50000",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
},
"axm.superadmin.webapp": {
    "redirectUris": [
        "http://localhost:50001",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

### 6.2 Platform environment.json (SPA API URLs)

**File:** `backend/axm.platform/wwwroot/environments/environment.json`

The Platform SPA uses these URLs for API calls. When accessing through the proxy, they must point to the proxy URLs:

| Field | Value |
|-------|-------|
| `apiUrl` | `http://axm.DOMAIN:PROXY_PORT` |
| `authApiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |
| `apiVnHost` | `http://vnhost.DOMAIN:PROXY_PORT` |

### 6.3 SuperAdmin environment.json (SPA API URLs)

**File:** `backend/axm.superadmin/wwwroot/web/environments/environment.json`

| Field | Value |
|-------|-------|
| `apiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |
| `authApiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |
| `axManagerUrl` | `http://axm.DOMAIN:PROXY_PORT` |

### 6.4 SuperAdmin appsettings.Development.json (CORS + OpenIddict)

**File:** `backend/axm.superadmin/appsettings.Development.json`

**CORS:** Add the proxy origins to `AllowedOrigins`:

```json
"Cors": {
    "AllowedOrigins": [
        "http://localhost:50001",
        "http://localhost:50000",
        "http://axm.DOMAIN:PROXY_PORT",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

**OpenIddict redirect URIs:** Add the proxy URLs to both `RedirectUris` and `PostLogoutRedirectUris` for `axm.webapp` and `axm.superadmin.webapp`:

```json
"axm.webapp": {
    "RedirectUris": [
        "http://localhost:50000",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ],
    "PostLogoutRedirectUris": [
        "http://localhost:50000",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
},
"axm.superadmin.webapp": {
    "RedirectUris": [
        "http://localhost:50001",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ],
    "PostLogoutRedirectUris": [
        "http://localhost:50001",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

### 6.5 Platform appsettings.{Edition}.json (Auth authority)

**File:** `backend/axm.platform/appsettings.Plus.json` (or whichever edition: `Lite`, `Classic`, `Advanced`)

The Platform backend uses `Authority` and `BaseUrl` to build login/authorize redirect URLs. If these point to `localhost`, the "Get started" button will redirect to `localhost` instead of the proxy URL.

| Field | Value |
|-------|-------|
| `AxmAuthentication.Authority` | `http://superadmin.DOMAIN:PROXY_PORT` |
| `SUP.BaseUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |

### 6.6 AllowedHosts (Platform + SuperAdmin)

When the proxy sends the original `Host` header (e.g. `axm.DOMAIN:8080`) instead of `localhost`, ASP.NET/Kestrel may reject the request if `AllowedHosts` is restrictive.

**File:** `backend/axm.platform/appsettings.Development.json`
**File:** `backend/axm.superadmin/appsettings.Development.json`

Add to each file (top level):

```json
{
    "AllowedHosts": "localhost;axm.DOMAIN;axm.DOMAIN:PROXY_PORT;superadmin.DOMAIN;superadmin.DOMAIN:PROXY_PORT;vnhost.DOMAIN;vnhost.DOMAIN:PROXY_PORT;commnode.DOMAIN;commnode.DOMAIN:PROXY_PORT",
    ...rest of file...
}
```

Use semicolons to separate entries. Include both with and without the port.

### Configuration checklist

| File | Field(s) | What to set |
|------|----------|-------------|
| `data.json` | `openIdApplications.axm.webapp.redirectUris` | Add `http://axm.DOMAIN:PROXY_PORT` |
| `data.json` | `openIdApplications.axm.superadmin.webapp.redirectUris` | Add `http://superadmin.DOMAIN:PROXY_PORT` |
| Platform `environment.json` | `apiUrl`, `authApiUrl`, `apiVnHost` | Proxy URLs |
| SuperAdmin `environment.json` | `apiUrl`, `authApiUrl`, `axManagerUrl` | Proxy URLs |
| SuperAdmin `appsettings.Development.json` | `Cors.AllowedOrigins` | Add proxy origins |
| SuperAdmin `appsettings.Development.json` | `OpenIddict` RedirectUris + PostLogoutRedirectUris | Add proxy URLs |
| Platform `appsettings.{Edition}.json` | `AxmAuthentication.Authority`, `SUP.BaseUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |
| Platform `appsettings.Development.json` | `AllowedHosts` | All hostnames (with and without port) |
| SuperAdmin `appsettings.Development.json` | `AllowedHosts` | All hostnames (with and without port) |

> **Important:** After changing any `appsettings` or `environment.json` file, **restart the corresponding AXM application** for changes to take effect.

---

## 7. Windows Firewall

The server must allow inbound connections on the proxy port. By default, Windows Firewall blocks unsolicited inbound TCP connections.

### Check the network profile

The firewall has different rules per profile. Determine which profile your network adapter uses:

```powershell
Get-NetConnectionProfile
```

Look at `NetworkCategory`: it will be **Public**, **Private**, or **DomainAuthenticated**.

### Create the firewall rule

In an **Administrator** PowerShell:

```powershell
New-NetFirewallRule -DisplayName "AXM Proxy PROXY_PORT" -Direction Inbound -Protocol TCP -LocalPort PROXY_PORT -Action Allow -Profile Any
```

Replace `PROXY_PORT` with your port (e.g. `8080`).

Using `-Profile Any` ensures the rule applies regardless of network profile (Public, Private, or Domain). If you prefer to restrict it, use `-Profile Private,Domain` (but make sure your network is not set to Public).

### Verify

```powershell
Get-NetFirewallRule -DisplayName "AXM Proxy PROXY_PORT" | Select-Object DisplayName, Enabled, Profile, Action
```

### GUI alternative

1. Open **Windows Defender Firewall with Advanced Security** (`wf.msc`).
2. **Inbound Rules** -> **New Rule...**.
3. **Port** -> Next -> **TCP**, Specific local ports: `PROXY_PORT` -> Next.
4. **Allow the connection** -> Next.
5. Check appropriate profiles -> Next.
6. Name: e.g. "AXM Proxy 8080" -> Finish.

---

## 8. Starting the services

Start in this order: AXM backends first, then the proxy, then DNS (if using CoreDNS).

### 8.1 Start the AXM bundle

Use the bundle launcher (e.g. `axm.exe`, `dotnet run`, or however the bundle is started at your site). Verify the backends are listening:

```powershell
netstat -ano | findstr "50000 50001 50002"
```

You should see `LISTENING` entries for each port.

### 8.2 Start the reverse proxy

**nginx example:**

```powershell
cd C:\nginx
.\nginx.exe
```

Verify:

```powershell
netstat -ano | findstr "PROXY_PORT"
```

Should show `0.0.0.0:PROXY_PORT  LISTENING`. If it shows `127.0.0.1`, the proxy is only accessible locally; check the config.

**IIS:** Start the site in IIS Manager or restart the app pool.

### 8.3 Start CoreDNS (if using Option B)

In an **Administrator** PowerShell:

```powershell
cd C:\coredns
.\coredns.exe -conf Corefile
```

Verify:

```powershell
nslookup axm.DOMAIN 127.0.0.1
```

Should return `SERVER_IP`.

---

## 9. Client device setup

What each client device needs depends on the DNS option chosen in section 4.

### If using hosts files (Option A)

Edit the hosts file on **each client device** as described in section 4A.

### If using CoreDNS or client's own DNS (Option B or C)

- If CoreDNS is the DNS server and devices get DNS via DHCP pointing to `SERVER_IP`, no per-device setup is needed.
- If DNS is manual, set each device's DNS to the DNS server that has the records.

### Per-OS instructions

**Windows:**

1. Press **Win+R**, type `ncpa.cpl`, press Enter.
2. Right-click active adapter -> Properties.
3. Select **Internet Protocol Version 4 (TCP/IPv4)** -> Properties.
4. **Use the following DNS server addresses**: Preferred = `SERVER_IP` (or your DNS server). Alternate = `8.8.8.8` (optional fallback).
5. OK -> OK.

**Mac:**

System Preferences -> Network -> adapter -> DNS -> add `SERVER_IP`.

**Linux:**

Edit `/etc/resolv.conf` or use NetworkManager to set DNS to `SERVER_IP`.

**iPhone:**

Settings -> Wi-Fi -> tap (i) next to the network -> Configure DNS -> Manual -> add `SERVER_IP`.

**Android:**

Settings -> Wi-Fi -> long-press network -> Modify -> Advanced -> IP settings -> Static -> DNS 1 = `SERVER_IP`.

### Browser considerations

Some browsers (Chrome, Edge) use "Secure DNS" / "DNS over HTTPS" by default, which bypasses local DNS. If the browser cannot resolve your hostnames:

- **Chrome:** Settings -> Privacy and security -> Security -> Use secure DNS -> **Off** (or set to your DNS provider).
- **Edge:** Settings -> Privacy, search, and services -> Security -> Use secure DNS -> **Off**.
- **Firefox:** Settings -> Privacy & Security -> DNS over HTTPS -> **Off**.

---

## 10. Verification and testing

Run these checks in order. If a step fails, fix it before proceeding.

### Step 1: DNS resolution

On a **client device**:

```powershell
ping axm.DOMAIN
```

- Should show `SERVER_IP` and get replies.
- If "could not find host": DNS is not working (check section 4).
- If IP is correct but "request timed out": network/firewall issue (check section 7).

### Step 2: Port connectivity

On a **client device** (replace IP and port):

```powershell
Test-NetConnection -ComputerName SERVER_IP -Port PROXY_PORT
```

- `TcpTestSucceeded : True` -> proxy is reachable.
- `TcpTestSucceeded : False` -> firewall blocking, proxy not running, or network issue. Check section 7 and section 8.

### Step 3: Browser access

Open in a browser:

- `http://axm.DOMAIN:PROXY_PORT` -> should load the Platform UI.
- `http://superadmin.DOMAIN:PROXY_PORT` -> should load the SuperAdmin UI.
- `http://vnhost.DOMAIN:PROXY_PORT` -> should load VnHost (if running).

If you get a **502 Bad Gateway**: the proxy is working but the backend on that port is not running. Start the backend (section 8.1).

If you get the **nginx default page** or "Welcome to nginx": the proxy is not using the AXM config. Check that `axm.conf` is included and nginx was restarted.

### Step 4: Authentication flow

1. Open `http://axm.DOMAIN:PROXY_PORT`.
2. Click **Get started** (or the login button).
3. You should be redirected to `http://superadmin.DOMAIN:PROXY_PORT/login?...`.
4. After logging in, you should return to `http://axm.DOMAIN:PROXY_PORT`.

If clicking "Get started" does nothing (no redirect):
- Check `environment.json` (section 6.2): `authApiUrl` must point to `http://superadmin.DOMAIN:PROXY_PORT`.
- Check `appsettings.{Edition}.json` (section 6.5): `Authority` and `BaseUrl` must point to `http://superadmin.DOMAIN:PROXY_PORT`.
- Restart the Platform after changes.

If the redirect goes to `localhost:50001` instead of the proxy URL:
- The backend is building URLs using its local address. Update `Authority` and `BaseUrl` (section 6.5) and the `environment.json` files (sections 6.2, 6.3).

If login fails with CORS errors:
- Check `AllowedOrigins` in SuperAdmin `appsettings.Development.json` (section 6.4).
- Check that the proxy is sending `X-Forwarded-Host` with the correct host and port.

If login redirects but returns an error about invalid `redirect_uri`:
- Add the proxy URL to `redirectUris` in `data.json` and in the OpenIddict `RedirectUris` in SuperAdmin `appsettings.Development.json` (sections 6.1, 6.4).
- Restart SuperAdmin after changes.

---

## 11. Troubleshooting

### DNS issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "This site can't be reached" / DNS_PROBE_FINISHED_NXDOMAIN | Hostname not in DNS or hosts file | Add hosts entry or DNS record (section 4) |
| `nslookup` works but browser does not | Browser using Secure DNS / DoH | Disable Secure DNS in browser settings (section 9) |
| CoreDNS: "bind: permission denied" | Port 53 needs Administrator | Run PowerShell as Administrator |
| CoreDNS: "bind: address already in use" | Another DNS service on port 53 | Stop the conflicting service (e.g. Windows DNS Client) or use a different port |

### Proxy issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Backend not running on that port | Start the AXM application; verify with `netstat` |
| 404 Not Found (from nginx) | Old nginx process with stale config | Kill all nginx (`taskkill /IM nginx.exe /F`) and restart |
| nginx won't start | Port already in use or config syntax error | Run `nginx.exe -t` to test config; check `logs\error.log` |
| Default page instead of AXM | `axm.conf` not included or hostname mismatch | Check `nginx.conf` has `include axm.conf;` and `server_name` matches your hostname exactly |
| Connection refused on PROXY_PORT | Proxy not running or firewall blocking | Check `netstat` for LISTENING; check firewall rule (section 7) |

### Authentication / redirect issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Get started" does nothing | `authApiUrl` or `Authority` still points to localhost | Update `environment.json` and `appsettings.{Edition}.json` (sections 6.2, 6.5); restart |
| Redirect goes to `localhost:50001` | Backend builds URLs using local address | Update `Authority` and `BaseUrl` in `appsettings.{Edition}.json` (section 6.5); restart |
| CORS error in browser console | Proxy origin not in `AllowedOrigins` | Add `http://axm.DOMAIN:PROXY_PORT` and `http://superadmin.DOMAIN:PROXY_PORT` to CORS config (section 6.4); restart SuperAdmin |
| "invalid redirect_uri" after login | Proxy URL not in `redirectUris` | Add to `data.json` and OpenIddict config (sections 6.1, 6.4); restart SuperAdmin |
| Kestrel rejects request (400 Bad Request) | `Host` header not in `AllowedHosts` | Add hostnames to `AllowedHosts` in `appsettings.Development.json` (section 6.6); restart |

### Network issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Test-NetConnection` returns False | Firewall, different subnet, or proxy not running | Check firewall rule and network profile (section 7); verify devices are on the same subnet |
| `ping` times out | Different subnet or no route | Confirm both devices are on the same network; check with `ipconfig` on both |
| Works on server but not from other devices | Firewall rule missing or wrong profile | Re-create rule with `-Profile Any` (section 7); verify with `Get-NetFirewallRule` |

---

## 12. Running as Windows services

For production use, run the proxy and DNS server as Windows services so they start automatically at boot.

**NSSM** (Non-Sucking Service Manager) is a simple tool for this:

1. Download from https://nssm.cc/download.
2. Extract `nssm.exe` (win64 version).

**Install nginx as a service (Administrator PowerShell):**

```powershell
nssm install nginx "C:\nginx\nginx.exe"
nssm set nginx AppDirectory "C:\nginx"
nssm start nginx
```

**Install CoreDNS as a service (Administrator PowerShell):**

```powershell
nssm install CoreDNS "C:\coredns\coredns.exe" "-conf" "C:\coredns\Corefile"
nssm set CoreDNS AppDirectory "C:\coredns"
nssm start CoreDNS
```

For full details, see `COREDNS-NGINX-LOCAL-ACCESS.md` in this repo.

---

## 13. Summary checklist

Use this checklist when deploying at a client site. Check off each item as completed.

### Planning

- [ ] Server LAN IP noted (`ipconfig`): _______________
- [ ] IP is static or has a DHCP reservation
- [ ] Hostnames chosen: axm._______, superadmin._______, vnhost._______, commnode._______
- [ ] Proxy port chosen: _______
- [ ] Backend ports confirmed from `data.json`: Platform _______, SuperAdmin _______, VnHost _______, CommNode _______

### DNS

- [ ] DNS method chosen: Hosts file / CoreDNS / Client DNS
- [ ] DNS records or hosts entries created for all hostnames -> SERVER_IP
- [ ] Verified: `ping axm.DOMAIN` returns SERVER_IP (from server and from a client)

### Reverse proxy

- [ ] Proxy software installed (nginx / IIS+ARR / other)
- [ ] Proxy config created with correct hostnames, backend ports, and forwarded headers
- [ ] Proxy config tested (`nginx -t` or equivalent)
- [ ] Proxy started and listening on PROXY_PORT (`netstat` shows `0.0.0.0:PROXY_PORT LISTENING`)

### AXM bundle configuration

- [ ] `data.json`: proxy URLs added to `redirectUris` for `axm.webapp` and `axm.superadmin.webapp`
- [ ] Platform `environment.json`: `apiUrl`, `authApiUrl`, `apiVnHost` set to proxy URLs
- [ ] SuperAdmin `environment.json`: `apiUrl`, `authApiUrl`, `axManagerUrl` set to proxy URLs
- [ ] SuperAdmin `appsettings.Development.json`: proxy origins added to CORS `AllowedOrigins`
- [ ] SuperAdmin `appsettings.Development.json`: proxy URLs added to OpenIddict RedirectUris and PostLogoutRedirectUris
- [ ] Platform `appsettings.{Edition}.json`: `Authority` and `BaseUrl` set to `http://superadmin.DOMAIN:PROXY_PORT`
- [ ] Platform `appsettings.Development.json`: `AllowedHosts` includes all hostnames
- [ ] SuperAdmin `appsettings.Development.json`: `AllowedHosts` includes all hostnames
- [ ] AXM applications restarted after config changes

### Firewall

- [ ] Inbound TCP rule created for PROXY_PORT
- [ ] Rule applies to the correct network profile (or "Any")
- [ ] Verified: `Test-NetConnection -ComputerName SERVER_IP -Port PROXY_PORT` returns True from a client

### Client devices

- [ ] DNS configured on client devices (hosts file, DNS setting, or automatic via DHCP)
- [ ] Browser Secure DNS disabled if using local DNS
- [ ] `http://axm.DOMAIN:PROXY_PORT` loads the Platform UI from a client device
- [ ] `http://superadmin.DOMAIN:PROXY_PORT` loads the SuperAdmin UI from a client device
- [ ] "Get started" / login flow works end-to-end (redirect to SuperAdmin, login, return to Platform)

### Optional

- [ ] Proxy and DNS installed as Windows services (auto-start at boot)
- [ ] Tested after server reboot: services start, URLs accessible
