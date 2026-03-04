# axm.gmojsoski.com unreachable – fix checklist

## What we found
- **DNS**: axm.gmojsoski.com resolves to Cloudflare ✓  
- **Cloudflared**: Service is Running ✓  
- **IIS**: Listening on 8080 ✓  
- **Backends**: Only **50000** and **50001** are listening (not 50080/50081)

So web.config was updated to send traffic to **http://127.0.0.1:50000** and **http://127.0.0.1:50001** (the ports that are actually in use). Your bundle has `"useHttps": false` in data.json, so the apps may be on HTTP.

---

## Do these steps in order

### 1. Copy web.config to IIS
Copy the file from this folder to the site root:
```
From: lenovo-homelab\axm-windows\web.config
To:   C:\inetpub\axm-demo\web.config
```
Overwrite the existing file. Then recycle the site or app pool in IIS (or restart the “AXM Demo” site).

### 2. Confirm Cloudflare Tunnel hostname
In **Cloudflare Zero Trust** → **Networks** → **Tunnels** → your tunnel → **Public Hostnames**:

You must have:
- **Subdomain**: `axm`  
- **Domain**: `gmojsoski.com`  
- **Service type**: HTTP  
- **URL**: `localhost:8080` (or `http://localhost:8080`)

If that row is missing, add it and save.

### 3. Test from this PC (same machine)
In **PowerShell**:
```powershell
Invoke-WebRequest -Uri "http://localhost:8080/" -Headers @{ Host = "axm.gmojsoski.com" } -UseBasicParsing -TimeoutSec 10
```
- If you get **200** or a normal HTML response → IIS and backend are fine; the problem is likely tunnel or DNS.
- If you get **502** or **503** → backend may be HTTPS-only; see “If still 502” below.
- If you get **500** → check Event Viewer (Windows Logs → Application) and IIS Failed Request Tracing for the real error.

### 4. Test from the internet
Open **https://axm.gmojsoski.com** in a browser (from another network or phone off Wi‑Fi).  
If it works from step 3 but not here, the tunnel or DNS is the issue.

---

## If you still get 502 (Bad Gateway)

Then the apps are probably **HTTPS-only** on 50000/50001. Two options:

**Option A – Trust the backend certificate (so IIS can use HTTPS)**  
1. Run (as Administrator):  
   `dotnet dev-certs https -ep "%TEMP%\axm-backend.cer" -f`  
2. Then:  
   `certutil -addstore -f "Root" "%TEMP%\axm-backend.cer"`  
3. Change web.config back to **https://localhost:50000** and **https://localhost:50001** (instead of http and 127.0.0.1), copy to `C:\inetpub\axm-demo\web.config`, recycle the site.

**Option B – Use HTTP backend ports 50080/50081**  
1. Ensure the **Http_LocalProxy** endpoints are in the appsettings that the bundle actually uses (Platform and SuperAdmin), then **restart the AXM bundle** so the apps listen on **50080** and **50081**.  
2. In web.config, point axm to **http://127.0.0.1:50080** and superadmin to **http://127.0.0.1:50081**, copy to `C:\inetpub\axm-demo\web.config`, recycle the site.

---

## Quick copy command (run from repo root)
```powershell
Copy-Item "C:\Users\User1\Desktop\Cursor\lenovo-homelab\axm-windows\web.config" -Destination "C:\inetpub\axm-demo\web.config" -Force
```
