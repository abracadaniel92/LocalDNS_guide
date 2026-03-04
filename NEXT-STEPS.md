# Next steps: IIS site + Cloudflare Tunnel for AXM

You’ve installed IIS (with WebSocket, URL Rewrite, ARR), enabled the proxy, and installed cloudflared. Do the following in order.

---

## Step 1: Create the IIS site and add web.config

1. **Create the site folder** (e.g. for the site root):
   ```
   C:\inetpub\axm-demo
   ```
   Create the folder if it doesn’t exist.

2. **Copy web.config** from this folder into that root:
   ```
   Copy: lenovo-homelab\axm-windows\web.config  →  C:\inetpub\axm-demo\web.config
   ```

3. **Create the site in IIS Manager** (`Win+R` → `inetmgr`):
   - Right‑click **Sites** → **Add Website**
   - **Site name:** e.g. `AXM Demo`
   - **Physical path:** `C:\inetpub\axm-demo`
   - **Binding:** Type **http**, Port **8080**, Host name leave blank (port 80 was already in use)
   - Click **OK**
   - Start the site if it isn’t running.

4. **Check AXM is running** on this PC:
   - Platform: https://localhost:50000
   - SuperAdmin: https://localhost:50001
   - VnHost (if used): https://localhost:50002  

   If any use **http** instead of **https**, edit `C:\inetpub\axm-demo\web.config` and change the `url="https://localhost:..."` to `url="http://localhost:..."` for that port.

---

## Step 2: (Optional) Test locally with hosts file

So that `app.axm.gmojsoski.com` etc. resolve to this PC:

1. Open **Notepad as Administrator**.
2. Open `C:\Windows\System32\drivers\etc\hosts`.
3. Add (use your PC’s LAN IP instead of 127.0.0.1 if you’ll test from another device):
   ```
   127.0.0.1    app.axm.gmojsoski.com
   127.0.0.1    admin.axm.gmojsoski.com
   127.0.0.1    vnhost.axm.gmojsoski.com
   ```
4. Save.

Then open http://app.axm.gmojsoski.com:8080 in a browser (AXM Demo site is on port 8080). You should hit the Platform app via IIS.

---

## Step 3: Create the Cloudflare Tunnel and get credentials

1. Go to **Cloudflare Zero Trust**: https://one.dash.cloudflare.com (or Cloudflare dashboard → Zero Trust).
2. **Networks** → **Tunnels** → **Create a tunnel**.
3. Choose **Cloudflared**.
4. **Tunnel name:** e.g. `axm-windows`.
5. Click **Save tunnel**. You’ll get:
   - A **tunnel ID** (UUID).
   - A **credentials file** (JSON). Download it.
6. **Save the JSON** as:
   ```
   %USERPROFILE%\.cloudflared\<tunnel-id>.json
   ```
   Example: `C:\Users\User1\.cloudflared\abcd1234-5678-90ab-cdef-1234567890ab.json`  
   Create the folder `.cloudflared` in your user profile if it doesn’t exist.

---

## Step 4: Create the tunnel config file

1. Create (or edit) the config file:
   ```
   %USERPROFILE%\.cloudflared\config.yml
   ```
   Example: `C:\Users\User1\.cloudflared\config.yml`

2. **If this PC only runs AXM** (no other tunnel), use this (replace the two placeholders):

   ```yaml
   tunnel: axm-windows
   credentials-file: C:\Users\User1\.cloudflared\<TUNNEL-ID>.json

   ingress:
     - hostname: app.axm.gmojsoski.com
       service: http://localhost:8080
     - hostname: admin.axm.gmojsoski.com
       service: http://localhost:8080
     - hostname: vnhost.axm.gmojsoski.com
       service: http://localhost:8080
     - service: http_status:404
   ```

   Replace:
   - `axm-windows` with the tunnel name you chose.
   - `<TUNNEL-ID>` with the actual tunnel UUID (same as the JSON filename).

3. **If you already have a tunnel config** (e.g. from your Linux server), you can either:
   - Run a **second tunnel** on this Windows PC with the config above (recommended: one tunnel per machine), or
   - Add the three `hostname`/`service` lines from `cloudflare-ingress-axm.yml` to your existing config and run that tunnel on this PC. The catch‑all `service: http_status:404` must stay last.

---

## Step 5: Create DNS records in Cloudflare

1. In **Cloudflare Dashboard** → your domain **gmojsoski.com** → **DNS** → **Records**.
2. Add three **CNAME** records:

   | Type | Name        | Target                          | Proxy status |
   |------|-------------|----------------------------------|--------------|
   | CNAME | app.axm   | \<tunnel-id>.cfargotunnel.com    | Proxied (orange) |
   | CNAME | admin.axm | \<tunnel-id>.cfargotunnel.com    | Proxied       |
   | CNAME | vnhost.axm| \<tunnel-id>.cfargotunnel.com    | Proxied       |

   **Target:** the tunnel FQDN from the Zero Trust tunnel page, e.g. `abcd1234-5678-90ab-cdef-1234567890ab.cfargotunnel.com`.  
   **Name:** `app.axm` means `app.axm.gmojsoski.com` when the zone is `gmojsoski.com`.

---

## Step 6: Run cloudflared

**One-off (foreground):**

```powershell
cloudflared tunnel --config %USERPROFILE%\.cloudflared\config.yml run
```

Leave the window open. You should see “Registered tunnel connection” and then traffic will go: Internet → Cloudflare → tunnel → IIS (port 8080) → AXM (50000, 50001, 50002).

**As a Windows service (starts at boot):**

```powershell
cloudflared service install
```

(Ensure `config.yml` is at `%USERPROFILE%\.cloudflared\config.yml`; the service uses that by default.)

Then test in a browser (from anywhere):

- https://app.axm.gmojsoski.com  
- https://admin.axm.gmojsoski.com  
- https://vnhost.axm.gmojsoski.com  

---

## Step 7: AXM app configuration (CORS & OpenID Connect)

In your AXM and identity provider configuration, use the **public** hostnames, not localhost:

- **CORS AllowedOrigins:**  
  `https://app.axm.gmojsoski.com`, `https://admin.axm.gmojsoski.com`
- **OpenID Connect:** Authority, redirect URIs, post‑logout URIs: use  
  `https://app.axm.gmojsoski.com` and `https://admin.axm.gmojsoski.com`

See the AXM Manual Configuration docs for the exact appsettings/UI fields.

---

## Quick checklist

- [ ] Folder `C:\inetpub\axm-demo` exists and contains `web.config`
- [ ] IIS site “AXM Demo” created, path `C:\inetpub\axm-demo`, binding **http :8080**, site started
- [ ] AXM backends running on 50000, 50001 (and 50002 if using VnHost)
- [ ] Tunnel created in Zero Trust; credentials JSON in `%USERPROFILE%\.cloudflared\<id>.json`
- [ ] `%USERPROFILE%\.cloudflared\config.yml` has tunnel name, credentials-file path, and the three hostnames → `http://localhost:8080` + catch‑all
- [ ] DNS: CNAME `app.axm`, `admin.axm`, `vnhost.axm` → `<tunnel-id>.cfargotunnel.com` (Proxied)
- [ ] `cloudflared tunnel --config ... run` (or service) is running
- [ ] CORS and OIDC in AXM use the public hostnames above

If anything doesn’t work, check: IIS site running, AXM processes listening, config.yml path and tunnel ID, and DNS propagated. Tunnel logs in the cloudflared window will show connection errors.
