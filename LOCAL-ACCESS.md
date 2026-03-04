# Local network access (without public domain)

## What we're using now

- **No local DNS** is configured in this setup. Everything is public:
  - **Cloudflare DNS**: `axm`, `superadmin`, `vnhost`.gmojsoski.com → CNAME to your tunnel (Proxied).
  - **Cloudflare Tunnel** → `http://localhost:8080` on the AXM machine.
  - **nginx** listens only on **8080** (localhost), so only the tunnel (and localhost) can reach it.

So from another device on your LAN, when you open `https://axm.gmojsoski.com`, the request goes: your device → internet → Cloudflare → tunnel → your server. It works but traffic leaves and comes back.

---

## Client-friendly local DNS options

Ways to resolve `axm.gmojsoski.com` (and superadmin/vnhost) to your server’s LAN IP **without** homelab tools like Pi-hole. Pick one that fits the client’s environment.

| Option | Best for | What to do |
|--------|----------|------------|
| **Router local DNS** | Any site with a router that supports it | In the router admin, find “Local DNS”, “Static DNS”, “DNS rewrite”, “Hosts”, or “Custom DNS records”. Add `axm.gmojsoski.com`, `superadmin.gmojsoski.com`, `vnhost.gmojsoski.com` → server LAN IP (e.g. `192.168.1.100`). Clients get DNS from the router (DHCP), so they pick this up automatically. Common on many business and prosumer routers (UniFi, MikroTik, Asus, TP-Link, Netgear, etc.). |
| **Windows Server DNS** | Sites that already have a Windows domain and DNS | On the server running the DNS role, add **A** records (or CNAME) for `axm.gmojsoski.com`, `superadmin.gmojsoski.com`, `vnhost.gmojsoski.com` pointing to the AXM server’s LAN IP. Ensure clients use this server as DNS (DHCP or GPO). Standard, supportable, no extra hardware. |
| **Hosts file** | Few PCs, no router/DNS control | On each Windows PC: edit `C:\Windows\System32\drivers\etc\hosts` as Administrator. Add one line: `192.168.1.100   axm.gmojsoski.com superadmin.gmojsoski.com vnhost.gmojsoski.com` (use the real server IP). On Mac/Linux: `/etc/hosts` with the same line. No extra services; manual per machine. |
| **Group Policy (GPO)** | Active Directory, many PCs | Use a GPO to deploy the hosts file content (Group Policy Preference “Files” or a startup script that writes the line into `hosts`). One-time GPO setup; all domain PCs get the entries. |
| **DNS on a small server/VM** | Need a dedicated DNS server | Run a lightweight DNS server (e.g. Windows Server DNS, or dnsmasq/CoreDNS on Linux) with A records for the three hostnames → server IP. Point client DNS (DHCP) to this server. More setup, but no “homelab” product name. |

After local DNS is in place, **nginx on the AXM server** must listen on **80/443** for direct LAN access (see Option 1 below); otherwise browsers on the LAN have no service on that IP.

---

## Cloudflare and similar: “local” or split DNS

### Cloudflare (Zero Trust / WARP)

Cloudflare doesn’t host your internal A records. It can **send** DNS for your domain to a DNS server you specify:

- **Local Domain Fallback** (Zero Trust): On devices that use the **WARP** client, you configure a domain (e.g. `gmojsoski.com`) and the IP(s) of the client’s **private DNS server**. All `*.gmojsoski.com` queries from that device then go to that server instead of Cloudflare. So:
  - You still need a DNS server (router, Windows Server, hosts file, etc.) that has the A records for `axm`, `superadmin`, `vnhost`.gmojsoski.com → server LAN IP.
  - Cloudflare only says: “When WARP is on, resolve this domain via this IP.”
- **Resolver policies** (Enterprise): Same idea but in the cloud: Gateway routes matching DNS to your custom resolvers. You still run the DNS; Cloudflare routes to it.

So Cloudflare gives you **split DNS** (use the client’s local DNS for your domain when they’re on WARP), not a fully managed “local DNS” product. Useful if the client already uses or will adopt WARP.

**Where to set it:** Zero Trust → **Team & Resources** → **Devices** → **Device profiles** → [profile] → **Configure** → **Local Domain Fallback** → add domain `gmojsoski.com` and the client’s DNS server IP(s).

### Similar to Cloudflare

- **Tailscale**: **MagicDNS** gives each device a name (e.g. `axm-server.tailnet.ts.net`) that resolves over the Tailscale network. No need to run your own DNS for that. You can also use **Split DNS** so that, on a given network, `*.gmojsoski.com` is resolved by a local DNS server. Good if the client is open to Tailscale for remote/LAN access; hostnames are Tailscale’s unless you combine with split DNS + local DNS.
- **Other**: Solutions like **Azure DNS Private Resolver**, **AWS Route 53 Resolver** (with Outbound/Inbound), or **Infoblox/BlueCat** are for enterprises with existing private DNS; they’re not “Cloudflare-like” SaaS for small sites.

---

## Options for local-only access (no domain / stay on LAN)

### Option 1: Same hostnames, local DNS + nginx on 80/443 (recommended)

Use the **same** hostnames (`axm.gmojsoski.com`, etc.) on the LAN by resolving them to your server’s LAN IP and serving them with nginx on the server.

1. **Local DNS**: Use one of the options in the table above (router, Windows Server DNS, hosts file, GPO, or DNS server). Entries needed: `axm.gmojsoski.com`, `superadmin.gmojsoski.com`, `vnhost.gmojsoski.com` → server LAN IP (e.g. `192.168.1.100`).

2. **nginx on the server** must listen on **port 80** (and optionally **443**) for direct LAN access, not only 8080. Right now nginx only listens on 8080 for the tunnel. So:
   - Add a second `listen 80;` (and optionally `listen 443 ssl;`) to the same server blocks in `axm.conf`, **or**
   - Add a separate `server { listen 80; server_name axm.gmojsoski.com ... }` (and 443) that proxy to 50000/50001/50002.

3. **HTTPS on LAN**: Browsers will connect to your server’s IP on port 443. You don’t have Cloudflare’s private key, so you need a **self-signed certificate** (or a local CA like mkcert) for `axm.gmojsoski.com`, `superadmin.gmojsoski.com`, `vnhost.gmojsoski.com`. Then configure nginx to use that cert for `listen 443 ssl`. Users will get a one-time “unsafe” warning; after accepting, it works.  
   If you use **HTTP only** on LAN (port 80), no cert is needed, but the AXM apps are configured for **https://** in `environment.json`, so they may redirect or call APIs over HTTPS; then you’d need 443 with a self-signed cert anyway.

Result: From a device on the LAN, `https://axm.gmojsoski.com` (and superadmin/vnhost) resolve to your server; nginx on 443 serves the apps; traffic never leaves the LAN.

---

### Option 2: Local-only hostnames (e.g. axm.lan)

If you don’t want to use the real domain on LAN at all:

1. Pick hostnames that only exist locally, e.g. `axm.lan`, `superadmin.lan`, `vnhost.lan`.
2. **Local DNS or hosts file**: Resolve those to your server’s LAN IP.
3. **nginx**: Add `server_name` entries for `axm.lan`, `superadmin.lan`, `vnhost.lan` (same proxy rules to 50000, 50001, 50002). Listen on 80 and/or 443.
4. **SSL**: Use a self-signed (or mkcert) cert for `*.lan` or each name.
5. **AXM config**: The apps’ `environment.json` and CORS/OIDC are set for `https://superadmin.gmojsoski.com` etc. To use `axm.lan` / `superadmin.lan` you’d have to add those URLs to CORS, redirect URIs, and update `environment.json` (and similar) to use `https://superadmin.lan` when you want to use the .lan hostnames. So Option 1 (same hostnames, local DNS) is usually simpler.

---

### Option 3: Use the public URLs from the LAN (no local DNS)

Do nothing. From any device (including on your LAN), use:

- `https://axm.gmojsoski.com`
- `https://superadmin.gmojsoski.com`
- `https://vnhost.gmojsoski.com`

DNS resolves to Cloudflare; traffic goes: device → internet → Cloudflare → tunnel → your server. No local DNS, no nginx on 80/443. Works even without a “domain” on the LAN; you’re just using the public domain. Downside: traffic leaves the LAN and latency may be slightly higher.

---

## Summary

| Goal                         | Approach                                                                 |
|-----------------------------|--------------------------------------------------------------------------|
| **What we use now**         | No local DNS; public Cloudflare DNS + tunnel; nginx only on 8080.         |
| **Access on LAN “like at home”** | Option 1: local DNS (or hosts) + nginx on 80/443 with self-signed certs. |
| **Access on LAN, no config**| Option 3: keep using the public URLs from the LAN.                      |

If you tell me your server’s LAN IP and whether you prefer HTTP-only or HTTPS (self-signed) on the LAN, I can give exact nginx snippets for Option 1.
