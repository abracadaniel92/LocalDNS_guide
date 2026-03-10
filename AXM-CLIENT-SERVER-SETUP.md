# AXM Client-Server Environment Setup Guide

Comprehensive guide for deploying AXM on a Windows server and making it accessible to LAN clients by hostname through a reverse proxy. Written for SimonsVoss engineers deploying at client sites and for client IT administrators.

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Understanding the AXM bundle](#2-understanding-the-axm-bundle)
3. [Architecture overview](#3-architecture-overview)
4. [Prerequisites](#4-prerequisites)
5. [Planning](#5-planning)
6. [DNS configuration](#6-dns-configuration)
7. [Reverse proxy requirements](#7-reverse-proxy-requirements)
8. [AXM bundle configuration for proxy access](#8-axm-bundle-configuration-for-proxy-access)
9. [Windows Firewall](#9-windows-firewall)
10. [Starting and verifying](#10-starting-and-verifying)
11. [Client device setup](#11-client-device-setup)
12. [Troubleshooting](#12-troubleshooting)
13. [Deployment checklist](#13-deployment-checklist)

---

## 1. Introduction

### Purpose and audience

AXM runs several backend applications on a single Windows PC (the "server"). Each application listens on its own port (e.g. 50000, 50001). Accessing `http://serverip:50000` works on the server itself, but is not practical for end users or multiple client devices on the network.

This guide sets up:

- **DNS** so that friendly hostnames resolve to the server.
- **A reverse proxy** that listens on one port and routes requests by hostname to the correct backend.
- **AXM configuration** so that login, CORS, and redirect flows work through the proxy.

After setup, users open `http://axm.DOMAIN:PROXY_PORT` in a browser and everything works transparently.

This guide is **tool-agnostic**. It describes the requirements each component must meet rather than prescribing a specific product. Use whichever reverse proxy and DNS solution fits your environment.

### Placeholder reference

The following placeholders are used throughout this guide. **Replace them with your actual values** everywhere they appear.

| Placeholder | Meaning | Example |
|-------------|---------|---------|
| `DOMAIN` | The domain suffix for your hostnames | `lan`, `local`, `company.internal` |
| `SERVER_IP` | The server's static LAN IPv4 address | `192.168.1.100` |
| `PROXY_PORT` | The port the reverse proxy listens on | `8080` |
| `PLATFORM_PORT` | Port for AXM Platform (check `data.json`) | `50000` |
| `SUPERADMIN_PORT` | Port for SuperAdmin (check `data.json`) | `50001` |
| `VNHOST_PORT` | Port for VnHost (check `data.json`) | `50002` |
| `COMMNODE_PORT` | Port for CommNode (check `data.json`) | `60123` |

---

## 2. Understanding the AXM bundle

Before configuring anything, it is important to understand what the AXM bundle contains and how it is structured. This section describes the bundle layout, the role of each application, and where configuration lives.

### 2.1 Bundle folder structure

The AXM bundle is a self-contained folder. Its top-level layout:

```
AXM-Bundle/
├── data.json            # Bundle config: edition, ports, OpenID clients
├── backend/
│   ├── axm.platform/          # Platform (main web application)
│   ├── axm.superadmin/        # SuperAdmin (authentication + admin)
│   ├── axm.vnhost/            # VnHost (virtual network host)
│   ├── axm.commnode/          # CommNode (communication node)
│   └── axm.virtualcommnode/   # Virtual CommNode
└── logs/
    ├── axm.platform/
    ├── axm.superadmin/
    ├── axm.commnode/
    ├── axm.virtualcommnode/
    └── axm.vnhost/
```

The launcher executable is separate from this folder. It reads `data.json` to find and start each application.

### 2.2 Application roles and default ports

| Application | Default port | Role |
|-------------|-------------|------|
| **Platform** (`axm.platform`) | 50000 | The main web application that end users interact with. Serves an Angular SPA and backend APIs. |
| **SuperAdmin** (`axm.superadmin`) | 50001 | Authentication server (OpenID Connect via OpenIddict) and administration interface. All login and token flows go through SuperAdmin. |
| **VnHost** (`axm.vnhost`) | 50002 | Virtual Network Host server for lock communication. |
| **CommNode** (`axm.commnode`) | 60123 | Communication node for device communication. |
| **VirtualCommNode** (`axm.virtualcommnode`) | 60124 | Virtual communication node. |

Ports are defined in `data.json` at the bundle root. **Always check this file for actual values**; they may differ per installation.

### 2.3 Key configuration files

Each backend application has its own configuration files. The following are the ones relevant to reverse proxy and network setup.

**Bundle root:**

| File | Purpose |
|------|---------|
| `data.json` | Edition, environment, application list, ports, and OpenID client definitions (including `redirectUris`). |

**Platform** (`backend/axm.platform/`):

| File | Purpose |
|------|---------|
| `appsettings.json` | Base configuration. |
| `appsettings.{Edition}.json` | Edition-specific settings (e.g. `appsettings.Plus.json`). Contains `AxmAuthentication.Authority` and `SUP.BaseUrl` which control where the "Get started" button redirects. |
| `appsettings.Development.json` | Development/override settings. Contains `AllowedHosts`. |
| `wwwroot/environments/environment.json` | SPA configuration: `apiUrl`, `authApiUrl`, `apiVnHost`. The Angular frontend uses these URLs for all API calls. |

**SuperAdmin** (`backend/axm.superadmin/`):

| File | Purpose |
|------|---------|
| `appsettings.json` | Base configuration. |
| `appsettings.Development.json` | Contains CORS `AllowedOrigins`, OpenIddict `RedirectUris` and `PostLogoutRedirectUris`, and `AllowedHosts`. |
| `wwwroot/web/environments/environment.json` | SPA configuration: `apiUrl`, `authApiUrl`, `axManagerUrl`. |

### 2.4 Startup order and dependencies

`data.json` defines the startup order by priority:

1. **SuperAdmin** (priority 100) — starts first; all other apps depend on it for authentication.
2. **Platform** (priority 200) — depends on SuperAdmin.
3. **CommNode**, **VirtualCommNode**, **VnHost** (priority 300) — depend on both SuperAdmin and Platform.

Always start SuperAdmin before Platform, and Platform before the remaining services.

---

## 3. Architecture overview

### Network flow

```
Client browser
    |
    |  http://axm.DOMAIN:PROXY_PORT
    v
[DNS resolution]  axm.DOMAIN --> SERVER_IP
    |
    v
[Reverse proxy on SERVER_IP:PROXY_PORT]
    |  Routes by Host header:
    |    axm.DOMAIN         --> http://127.0.0.1:PLATFORM_PORT    (Platform)
    |    superadmin.DOMAIN   --> http://127.0.0.1:SUPERADMIN_PORT  (SuperAdmin)
    |    vnhost.DOMAIN       --> http://127.0.0.1:VNHOST_PORT      (VnHost)
    |    commnode.DOMAIN     --> http://127.0.0.1:COMMNODE_PORT    (CommNode)
    v
[AXM backend applications on localhost]
```

All client traffic enters through the reverse proxy on a single port. The proxy inspects the `Host` header and forwards the request to the correct backend. Clients never connect directly to the backend ports.

### Authentication flow

Understanding the authentication flow is critical for configuring AXM behind a proxy. When a user clicks "Get started" on the Platform, the following redirect chain occurs:

```
1. User opens http://axm.DOMAIN:PROXY_PORT
   -> Platform SPA loads in the browser

2. User clicks "Get started"
   -> Browser redirects to:
      http://superadmin.DOMAIN:PROXY_PORT/login?ReturnUrl=/api/v1/connect/authorize?
        client_id=axm.superadmin.webapp
        &redirect_uri=http://axm.DOMAIN:PROXY_PORT
        &response_type=code
        &scope=openid profile offline_access
        ...

3. User enters credentials on the SuperAdmin login page

4. SuperAdmin validates credentials and redirects back to:
   http://axm.DOMAIN:PROXY_PORT (the redirect_uri from step 2)
   with an authorization code

5. Platform exchanges the code for tokens with SuperAdmin (server-to-server)
```

This flow depends on several settings being consistent:

| What controls it | Setting | Must point to |
|-----------------|---------|---------------|
| Where "Get started" redirects | Platform `appsettings.{Edition}.json` → `AxmAuthentication.Authority` | `http://superadmin.DOMAIN:PROXY_PORT` |
| Where the SPA sends auth requests | Platform `environment.json` → `authApiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` |
| Which redirect URIs are accepted | SuperAdmin `appsettings.Development.json` → OpenIddict `RedirectUris` | Must include `http://axm.DOMAIN:PROXY_PORT` |
| Which origins are allowed (CORS) | SuperAdmin `appsettings.Development.json` → `Cors.AllowedOrigins` | Must include `http://axm.DOMAIN:PROXY_PORT` |

If any of these do not match, the login flow will break — the redirect will go to the wrong URL, the redirect URI will be rejected, or the browser will block the request due to CORS.

### Component roles

| Component | Role |
|-----------|------|
| **DNS** | Resolves hostnames to the server IP. Can be a hosts file, the client's existing DNS infrastructure (Active Directory, router DNS), or a dedicated DNS server. |
| **Reverse proxy** | Accepts HTTP on one port, inspects the `Host` header, and forwards to the correct backend. Can be any HTTP reverse proxy that supports host-based routing, forwarded headers, and WebSockets. |
| **AXM backends** | The actual applications (Kestrel/.NET). Each listens on `localhost` on its own port. They are not exposed directly to the network; the proxy handles external access. |

---

## 4. Prerequisites

Before starting, ensure the following:

- **Windows 10/11 or Windows Server** on the machine that will run AXM.
- **AXM bundle installed.** You should have a folder containing `data.json` and a `backend/` directory with the application folders.
- **Administrator access** on the server (needed for firewall rules, DNS on port 53 if using a DNS server, and hosts file edits).
- **Static or reserved LAN IP** on the server. If the server gets its IP via DHCP, create a **DHCP reservation** in the router/DHCP server so the IP does not change. DNS entries and client hosts files depend on a stable IP.
- **Chosen hostnames** for each application (see section 5).
- **A reverse proxy** installed that meets the requirements in section 7.
- **Ports confirmed:** open `data.json` and note the port for each application.

---

## 5. Planning

### 5.1 Choosing hostnames

Each AXM application gets its own hostname. All hostnames point to the same server IP; the reverse proxy uses the `Host` header to route to the correct backend.

**Naming conventions:**

| Style | Example | When to use |
|-------|---------|-------------|
| `.lan` suffix | `axm.lan`, `superadmin.lan` | Internal networks. `.lan` is not a reserved TLD, avoids mDNS conflicts. |
| `.internal` suffix | `axm.internal`, `superadmin.internal` | RFC 6762 reserves `.internal` for private use; safe from public DNS collisions. |
| `.local` suffix | `axm.local`, `superadmin.local` | Quick demos, isolated labs. Note: `.local` may conflict with mDNS/Bonjour on some networks. |
| Subdomain of a real domain | `axm.company.com`, `superadmin.company.com` | Production environments with centrally managed DNS (e.g. Active Directory). |

**Rules:**

1. **One hostname per application.** Platform, SuperAdmin, VnHost (and CommNode if used) each need a distinct hostname.
2. **All hostnames resolve to the same server IP.** The proxy distinguishes them by the `Host` header, not by IP.
3. **Pick a proxy port** (e.g. `8080`). All hostnames share this port. Avoid port 80 if another service already uses it.
4. **Be consistent.** Use the same hostnames everywhere: DNS, proxy config, AXM config files, browser URLs.

### 5.2 Choosing a proxy port

Choose a TCP port that is not already in use on the server. Common choices:

- **8080** — common HTTP alternative port.
- **80** — standard HTTP port (no port needed in the URL, but may conflict with existing services).
- **443** — standard HTTPS port (requires a TLS certificate on the proxy).

Check for conflicts:

```powershell
netstat -ano | findstr "LISTENING" | findstr ":8080"
```

If the port is in use, choose a different one.

### 5.3 Choosing a DNS strategy

| Approach | Scope | Effort | Best for |
|----------|-------|--------|----------|
| **Hosts file** | Per device | Low (edit one file per device) | Quick demos, 1-3 client devices |
| **Dedicated DNS server** | All devices that point DNS to it | Medium (run a DNS server on the AXM server or another machine) | Environments without existing DNS infrastructure |
| **Existing DNS infrastructure** | Network-wide (automatic) | Low-Medium (add A records) | Environments with Active Directory, router DNS, or similar |

---

## 6. DNS configuration

Clients must be able to resolve your chosen hostnames to `SERVER_IP`. Choose the approach that fits the environment.

### 6.1 Hosts file (per device)

Edit the hosts file on **each device** (including the server itself) that needs to access AXM.

**Windows** (run Notepad as Administrator):

1. Open `C:\Windows\System32\drivers\etc\hosts` (set file filter to "All Files").
2. Add one line:
   ```
   SERVER_IP    axm.DOMAIN superadmin.DOMAIN vnhost.DOMAIN commnode.DOMAIN
   ```
3. Save and close.

**Mac / Linux** (run as root or with sudo):

```bash
sudo nano /etc/hosts
# Add the same line, save.
```

### 6.2 Network-wide DNS

If the environment has existing DNS (Active Directory, Windows Server DNS, router DNS, or another DNS solution), add **A records** for each hostname pointing to `SERVER_IP`.

| Hostname | Record type | Value |
|----------|------------|-------|
| `axm.DOMAIN` | A | `SERVER_IP` |
| `superadmin.DOMAIN` | A | `SERVER_IP` |
| `vnhost.DOMAIN` | A | `SERVER_IP` |
| `commnode.DOMAIN` | A | `SERVER_IP` |

If no existing DNS infrastructure is available, a lightweight DNS server can be run on the AXM server itself. It should:

- Listen on UDP port 53.
- Resolve the chosen hostnames to `SERVER_IP`.
- Forward all other queries to an upstream DNS server (e.g. `8.8.8.8`).

Client devices (or the router's DHCP settings) are then pointed to `SERVER_IP` for DNS.

### 6.3 DNS verification

From a client device or the server itself:

```
ping axm.DOMAIN
```

The output should show `SERVER_IP`. If it shows a different address or "could not find host", DNS is not configured correctly.

If using a dedicated DNS server:

```
nslookup axm.DOMAIN SERVER_IP
```

Should return `SERVER_IP`.

---

## 7. Reverse proxy requirements

The reverse proxy sits between the client and the AXM backends. It listens on a single port, inspects the `Host` header, and forwards the request to the correct backend. This section describes the requirements any proxy must meet.

### 7.1 Listen on all interfaces

The proxy must listen on `0.0.0.0:PROXY_PORT` (all network interfaces), not just `127.0.0.1`. Binding to `0.0.0.0` ensures it accepts connections from other devices on the network.

### 7.2 Route by Host header

Each hostname maps to a different backend port on `127.0.0.1`:

| Incoming Host header | Forward to |
|---------------------|------------|
| `axm.DOMAIN` | `http://127.0.0.1:PLATFORM_PORT` |
| `superadmin.DOMAIN` | `http://127.0.0.1:SUPERADMIN_PORT` |
| `vnhost.DOMAIN` | `http://127.0.0.1:VNHOST_PORT` |
| `commnode.DOMAIN` | `http://127.0.0.1:COMMNODE_PORT` |

A default/fallback rule that routes unmatched hostnames to Platform is recommended so that accessing `http://SERVER_IP:PROXY_PORT` directly still works.

### 7.3 Forwarded headers

The proxy must set the following headers on every request so the backend knows the original client request:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Forwarded-Host` | Original host and port (e.g. `axm.DOMAIN:PROXY_PORT`) | Backend uses this for redirect URLs, CORS origin checks, and OpenID Connect flows. |
| `X-Forwarded-Proto` | `http` or `https` (the client's protocol) | Backend knows whether the client connected over HTTP or HTTPS. |
| `X-Forwarded-For` | Client IP address | Logging and access control. |
| `Host` | Original hostname (e.g. `axm.DOMAIN:PROXY_PORT`), or `localhost` if the backend only accepts localhost | Kestrel/ASP.NET uses this for URL generation. See note below. |

**Host header note:** By default, AXM's Kestrel server may only accept `Host: localhost`. There are two approaches:

- **Option A:** Send `Host: localhost` to the backend and set `X-Forwarded-Host` to the original hostname. The backend uses `X-Forwarded-Host` for URL generation if forwarded headers middleware is configured.
- **Option B:** Send the original `Host` header and add all hostnames to `AllowedHosts` in the backend's `appsettings` (see section 8.7).

### 7.4 WebSocket support

AXM uses SignalR, which requires WebSocket connections. The proxy must:

- Forward `Upgrade` and `Connection: upgrade` headers from the client to the backend.
- Use **HTTP/1.1** for the upstream connection (WebSockets require HTTP/1.1, not HTTP/2).
- Not buffer or interfere with the WebSocket data stream.

### 7.5 Timeouts

WebSocket connections are long-lived (they stay open for the duration of a user session). Set the read/proxy timeout to a high value (e.g. 86400 seconds / 24 hours) so the proxy does not prematurely close idle connections.

### 7.6 Proxy verification

After configuring the proxy, verify it is running and accessible:

```powershell
netstat -ano | findstr "PROXY_PORT"
```

The output should show `0.0.0.0:PROXY_PORT  LISTENING`. If it shows `127.0.0.1:PROXY_PORT`, the proxy is only accessible locally; adjust the configuration to bind to all interfaces.

---

## 8. AXM bundle configuration for proxy access

The AXM bundle must be told about the proxy URLs so that login redirects, CORS, and API calls work when accessed through the proxy. Without these changes, the "Get started" button will redirect to `localhost` instead of the proxy URL, login will fail due to unregistered redirect URIs, and cross-origin requests will be blocked.

All paths below are relative to the **bundle root** (the folder containing `data.json`).

### 8.1 The authentication redirect flow

When a user clicks "Get started" on the Platform, the following happens:

1. The Platform SPA reads `authApiUrl` from its `environment.json` and redirects the browser to the SuperAdmin login page at that URL.

2. The redirect URL includes OpenID Connect parameters:
   ```
   http://superadmin.DOMAIN:PROXY_PORT/login?ReturnUrl=/api/v1/connect/authorize?
       client_id=axm.superadmin.webapp
       &redirect_uri=http://axm.DOMAIN:PROXY_PORT
       &response_type=code
       &scope=openid profile offline_access
       &code_challenge=...
       &code_challenge_method=S256
   ```

3. The user enters credentials. SuperAdmin validates them and checks:
   - Is `http://axm.DOMAIN:PROXY_PORT` a **registered redirect URI** for client `axm.superadmin.webapp`? (Checked against OpenIddict `RedirectUris` in SuperAdmin's `appsettings.Development.json`.)
   - Is the request origin allowed by **CORS**? (Checked against `AllowedOrigins` in the same file.)

4. If both checks pass, SuperAdmin redirects the browser back to `http://axm.DOMAIN:PROXY_PORT` with an authorization code.

5. The Platform SPA exchanges the code for tokens by calling SuperAdmin's token endpoint.

**If any URL in this chain does not match the proxy URL, the flow breaks.** This is why every configuration change in this section matters.

### 8.2 data.json (OpenID redirect URIs)

**File:** `data.json`
**Section:** `openIdApplications`

Add the proxy URLs to `redirectUris` so the OpenID Connect flow accepts them:

```json
"axm.webapp": {
    "redirectUris": [
        "http://localhost:PLATFORM_PORT",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
},
"axm.superadmin.webapp": {
    "redirectUris": [
        "http://localhost:SUPERADMIN_PORT",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

**Why:** These URIs are seeded into the OpenIddict database. If the proxy URL is not listed, SuperAdmin will reject the login redirect with an "invalid redirect_uri" error.

### 8.3 Platform environment.json (SPA API URLs)

**File:** `backend/axm.platform/wwwroot/environments/environment.json`

The Platform SPA uses these URLs for API calls. When accessing through the proxy, they must point to the proxy URLs:

| Field | Value | Why |
|-------|-------|-----|
| `apiUrl` | `http://axm.DOMAIN:PROXY_PORT` | Where the SPA sends Platform API requests. |
| `authApiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` | Where the SPA redirects for login ("Get started" button). |
| `apiVnHost` | `http://vnhost.DOMAIN:PROXY_PORT` | Where the SPA sends VnHost API requests. |

**Why:** If these still point to `localhost`, the SPA will try to call `localhost` from the client's browser, which will fail because the backends are on the server, not the client.

### 8.4 SuperAdmin environment.json (SPA API URLs)

**File:** `backend/axm.superadmin/wwwroot/web/environments/environment.json`

| Field | Value | Why |
|-------|-------|-----|
| `apiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` | SuperAdmin SPA API calls. |
| `authApiUrl` | `http://superadmin.DOMAIN:PROXY_PORT` | SuperAdmin SPA auth requests. |
| `axManagerUrl` | `http://axm.DOMAIN:PROXY_PORT` | Link back to Platform from the SuperAdmin UI. |

### 8.5 SuperAdmin appsettings.Development.json (CORS + OpenIddict)

**File:** `backend/axm.superadmin/appsettings.Development.json`

**CORS:** Add the proxy origins to `AllowedOrigins`:

```json
"Cors": {
    "AllowedOrigins": [
        "http://localhost:SUPERADMIN_PORT",
        "http://localhost:PLATFORM_PORT",
        "http://axm.DOMAIN:PROXY_PORT",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

**Why:** The browser enforces CORS. When the Platform SPA (loaded from `http://axm.DOMAIN:PROXY_PORT`) makes API calls to SuperAdmin (`http://superadmin.DOMAIN:PROXY_PORT`), SuperAdmin must include that origin in its `Access-Control-Allow-Origin` response header. If the origin is not in `AllowedOrigins`, the browser blocks the request.

**OpenIddict redirect URIs:** Add the proxy URLs to both `RedirectUris` and `PostLogoutRedirectUris` for each client:

```json
"axm.webapp": {
    "RedirectUris": [
        "http://localhost:PLATFORM_PORT",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ],
    "PostLogoutRedirectUris": [
        "http://localhost:PLATFORM_PORT",
        "http://axm.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
},
"axm.superadmin.webapp": {
    "RedirectUris": [
        "http://localhost:SUPERADMIN_PORT",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ],
    "PostLogoutRedirectUris": [
        "http://localhost:SUPERADMIN_PORT",
        "http://superadmin.DOMAIN:PROXY_PORT",
        ...existing entries...
    ]
}
```

**Why:** OpenIddict validates that the `redirect_uri` in the authorization request matches one of the registered URIs. If the proxy URL is missing, login fails with "invalid redirect_uri". `PostLogoutRedirectUris` controls where the browser goes after logout.

### 8.6 Platform appsettings (Authority + BaseUrl)

**File:** `backend/axm.platform/appsettings.{Edition}.json` (e.g. `appsettings.Plus.json`)

| Field | Value | Why |
|-------|-------|-----|
| `AxmAuthentication.Authority` | `http://superadmin.DOMAIN:PROXY_PORT` | The Platform backend uses this to build the OpenID Connect authorization URL. This is where "Get started" ultimately redirects. |
| `SUP.BaseUrl` | `http://superadmin.DOMAIN:PROXY_PORT` | Used for server-to-server calls from Platform to SuperAdmin. |

**Why:** If `Authority` still points to `localhost:SUPERADMIN_PORT`, clicking "Get started" will redirect the browser to `localhost:SUPERADMIN_PORT`, which does not exist on the client's machine. The authority **must** be the proxy URL that is reachable from the client's browser.

### 8.7 AllowedHosts (Platform + SuperAdmin)

When the proxy sends the original `Host` header (e.g. `axm.DOMAIN:PROXY_PORT`) instead of `localhost`, ASP.NET/Kestrel may reject the request with a 400 Bad Request if `AllowedHosts` is restrictive.

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

**Note:** If your proxy sends `Host: localhost` to the backend (see section 7.3), this step may not be necessary, but it is good practice to include the hostnames regardless.

### 8.8 Configuration checklist

| File | Field(s) | What to set | Why |
|------|----------|-------------|-----|
| `data.json` | `openIdApplications.*.redirectUris` | Add proxy URLs | Login redirect URI validation |
| Platform `environment.json` | `apiUrl`, `authApiUrl`, `apiVnHost` | Proxy URLs | SPA API calls and login redirect |
| SuperAdmin `environment.json` | `apiUrl`, `authApiUrl`, `axManagerUrl` | Proxy URLs | SPA API calls and Platform link |
| SuperAdmin `appsettings.Development.json` | `Cors.AllowedOrigins` | Add proxy origins | Browser CORS enforcement |
| SuperAdmin `appsettings.Development.json` | OpenIddict `RedirectUris` + `PostLogoutRedirectUris` | Add proxy URLs | Login/logout redirect validation |
| Platform `appsettings.{Edition}.json` | `AxmAuthentication.Authority`, `SUP.BaseUrl` | `http://superadmin.DOMAIN:PROXY_PORT` | "Get started" redirect target |
| Platform `appsettings.Development.json` | `AllowedHosts` | All hostnames (with and without port) | Kestrel host filtering |
| SuperAdmin `appsettings.Development.json` | `AllowedHosts` | All hostnames (with and without port) | Kestrel host filtering |

> **Important:** After changing any `appsettings` or `environment.json` file, **restart the corresponding AXM application** for changes to take effect.

---

## 9. Windows Firewall

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

Replace `PROXY_PORT` with your port.

Using `-Profile Any` ensures the rule applies regardless of network profile. If you prefer to restrict it, use `-Profile Private,Domain` (but make sure your network is not set to Public).

### Verify

```powershell
Get-NetFirewallRule -DisplayName "AXM Proxy PROXY_PORT" | Select-Object DisplayName, Enabled, Profile, Action
```

### GUI alternative

1. Open **Windows Defender Firewall with Advanced Security** (`wf.msc`).
2. **Inbound Rules** → **New Rule...**.
3. **Port** → Next → **TCP**, Specific local ports: `PROXY_PORT` → Next.
4. **Allow the connection** → Next.
5. Check appropriate profiles → Next.
6. Name: e.g. "AXM Proxy" → Finish.

---

## 10. Starting and verifying

### 10.1 Start order

Start in this order:

1. **AXM backends** — SuperAdmin first, then Platform, then remaining services.
2. **Reverse proxy.**
3. **DNS server** (if using a dedicated DNS server).

### 10.2 Verify backends are running

```powershell
netstat -ano | findstr "PLATFORM_PORT SUPERADMIN_PORT VNHOST_PORT"
```

You should see `LISTENING` entries for each port.

### 10.3 Verify DNS resolution

From a **client device**:

```powershell
ping axm.DOMAIN
```

Should show `SERVER_IP` and get replies.

- If "could not find host": DNS is not working (check section 6).
- If IP is correct but "request timed out": network or firewall issue (check section 9).

### 10.4 Verify proxy connectivity

From a **client device**:

```powershell
Test-NetConnection -ComputerName SERVER_IP -Port PROXY_PORT
```

- `TcpTestSucceeded : True` → proxy is reachable.
- `TcpTestSucceeded : False` → firewall blocking, proxy not running, or network issue.

### 10.5 Verify browser access

Open in a browser:

- `http://axm.DOMAIN:PROXY_PORT` → should load the Platform UI.
- `http://superadmin.DOMAIN:PROXY_PORT` → should load the SuperAdmin UI.
- `http://vnhost.DOMAIN:PROXY_PORT` → should load VnHost.

### 10.6 Verify authentication flow

1. Open `http://axm.DOMAIN:PROXY_PORT`.
2. Click **Get started**.
3. The browser should redirect to `http://superadmin.DOMAIN:PROXY_PORT/login?ReturnUrl=...`.
4. After logging in, you should return to `http://axm.DOMAIN:PROXY_PORT`.

If this flow does not work, see section 12 (Troubleshooting).

---

## 11. Client device setup

What each client device needs depends on the DNS approach chosen in section 6.

### If using hosts files

Edit the hosts file on **each client device** as described in section 6.1.

### If using network-wide DNS

If DNS is handled by the network (Active Directory, router, or a dedicated DNS server), no per-device DNS setup is needed. Devices that get DNS via DHCP will resolve the hostnames automatically.

If DNS is set manually on each device, point the device's DNS to the server that has the records.

### Per-OS quick reference

**Windows:**

1. Press **Win+R**, type `ncpa.cpl`, press Enter.
2. Right-click active adapter → Properties.
3. Select **Internet Protocol Version 4 (TCP/IPv4)** → Properties.
4. **Use the following DNS server addresses**: Preferred = DNS server IP. Alternate = `8.8.8.8` (optional fallback).
5. OK → OK.

**Mac:**

System Preferences → Network → adapter → DNS → add the DNS server IP.

**Linux:**

Edit `/etc/resolv.conf` or use NetworkManager to set DNS.

**iPhone:**

Settings → Wi-Fi → tap (i) next to the network → Configure DNS → Manual → add the DNS server IP.

**Android:**

Settings → Wi-Fi → long-press network → Modify → Advanced → IP settings → Static → DNS 1 = DNS server IP.

### Browser considerations

Some browsers use "Secure DNS" / "DNS over HTTPS" by default, which bypasses local DNS and hosts files. If the browser cannot resolve your hostnames:

- **Chrome:** Settings → Privacy and security → Security → Use secure DNS → **Off** (or set to your DNS provider).
- **Edge:** Settings → Privacy, search, and services → Security → Use secure DNS → **Off**.
- **Firefox:** Settings → Privacy & Security → DNS over HTTPS → **Off**.

---

## 12. Troubleshooting

### DNS issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "This site can't be reached" / DNS_PROBE_FINISHED_NXDOMAIN | Hostname not in DNS or hosts file | Add hosts entry or DNS record (section 6) |
| `nslookup` works but browser does not | Browser using Secure DNS / DoH | Disable Secure DNS in browser settings (section 11) |
| DNS server: "permission denied" on port 53 | Port 53 needs Administrator | Run the DNS server as Administrator |
| DNS server: "address already in use" on port 53 | Another DNS service on port 53 | Stop the conflicting service or use a different port |

### Proxy issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Backend not running on that port | Start the AXM application; verify with `netstat` |
| 404 Not Found from the proxy | Proxy not configured for that hostname, or stale configuration | Check proxy config and restart the proxy |
| Default page instead of AXM | Proxy misconfiguration; hostname not matching any rule | Verify the proxy's hostname routing matches your chosen hostnames exactly |
| Connection refused on PROXY_PORT | Proxy not running or firewall blocking | Check `netstat` for LISTENING; check firewall rule (section 9) |
| Proxy only on 127.0.0.1 | Proxy bound to localhost only | Reconfigure to listen on `0.0.0.0:PROXY_PORT` |

### Authentication and redirect issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Get started" does nothing | `authApiUrl` or `Authority` still points to localhost | Update `environment.json` and `appsettings.{Edition}.json` (sections 8.3, 8.6); restart |
| Redirect goes to `localhost:SUPERADMIN_PORT` instead of proxy URL | Backend building URLs using its local address | Update `Authority` and `BaseUrl` in `appsettings.{Edition}.json` (section 8.6); restart |
| CORS error in browser console | Proxy origin not in `AllowedOrigins` | Add proxy origins to CORS config (section 8.5); restart SuperAdmin |
| "invalid redirect_uri" after login | Proxy URL not in `redirectUris` | Add to `data.json` and OpenIddict config (sections 8.2, 8.5); restart SuperAdmin |
| 400 Bad Request from Kestrel | `Host` header not in `AllowedHosts` | Add hostnames to `AllowedHosts` (section 8.7); restart the application |

### Network issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Test-NetConnection` returns False | Firewall, different subnet, or proxy not running | Check firewall rule and network profile (section 9); verify proxy is running |
| `ping` shows correct IP but times out | Different subnet or no route | Confirm both devices are on the same network; check with `ipconfig` on both |
| Works on server but not from other devices | Firewall rule missing or wrong profile | Re-create rule with `-Profile Any` (section 9) |

---

## 13. Deployment checklist

Use this checklist when deploying at a client site. Check off each item as completed.

### Planning

- [ ] Server LAN IP noted (`ipconfig`): _______________
- [ ] IP is static or has a DHCP reservation
- [ ] Hostnames chosen: axm._______, superadmin._______, vnhost._______, commnode._______
- [ ] Proxy port chosen: _______
- [ ] Backend ports confirmed from `data.json`: Platform _______, SuperAdmin _______, VnHost _______, CommNode _______

### DNS

- [ ] DNS method chosen: Hosts file / DNS server / Existing infrastructure
- [ ] DNS records or hosts entries created for all hostnames → SERVER_IP
- [ ] Verified: `ping axm.DOMAIN` returns SERVER_IP (from server and from a client)

### Reverse proxy

- [ ] Proxy software installed and configured
- [ ] Proxy routes by Host header to the correct backend ports
- [ ] Proxy sends forwarded headers (`X-Forwarded-Host`, `X-Forwarded-Proto`, `X-Forwarded-For`)
- [ ] Proxy supports WebSockets (`Upgrade` and `Connection` headers forwarded)
- [ ] Proxy timeout set to a high value for WebSocket connections
- [ ] Proxy started and listening on PROXY_PORT (`netstat` shows `0.0.0.0:PROXY_PORT LISTENING`)

### AXM bundle configuration

- [ ] `data.json`: proxy URLs added to `redirectUris` for `axm.webapp` and `axm.superadmin.webapp`
- [ ] Platform `environment.json`: `apiUrl`, `authApiUrl`, `apiVnHost` set to proxy URLs
- [ ] SuperAdmin `environment.json`: `apiUrl`, `authApiUrl`, `axManagerUrl` set to proxy URLs
- [ ] SuperAdmin `appsettings.Development.json`: proxy origins added to CORS `AllowedOrigins`
- [ ] SuperAdmin `appsettings.Development.json`: proxy URLs added to OpenIddict `RedirectUris` and `PostLogoutRedirectUris`
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
