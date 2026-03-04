# nginx reverse proxy for AXM (Windows)

Same behaviour as the IIS setup: host-based routing to Platform (50000), SuperAdmin (50001), VnHost (50002) with forwarded headers and WebSocket support.

## 1. Install nginx on Windows

1. Download the Windows zip from **https://nginx.org/en/download.html** (e.g. **nginx/Windows-1.28.x** or mainline).
2. Extract to a folder, e.g. **C:\nginx** (so you have `C:\nginx\nginx.exe`).
3. **Stop the IIS site** that uses port 8080 (AXM Demo), or change its binding so 8080 is free:
   - IIS Manager → Sites → AXM Demo → Bindings → remove or change the :8080 binding.

## 2. Use the AXM config

**Option A – Replace the default config**

1. Back up the original: copy `C:\nginx\conf\nginx.conf` to `nginx.conf.bak`.
2. Replace `C:\nginx\conf\nginx.conf` with the **nginx.conf** from this folder (it includes the AXM server blocks and listens on 8080).

**Option B – Include the AXM config**

1. Copy **axm.conf** from this folder to `C:\nginx\conf\axm.conf`.
2. Edit `C:\nginx\conf\nginx.conf`, find the `http {` block, and add this line **inside** it (e.g. before or after the existing `server` block):
   ```nginx
   include axm.conf;
   ```
3. In the same file, comment out or remove the default `listen 80` server if you want only 8080 for AXM.

## 3. Run nginx

Open **Command Prompt** or **PowerShell**:

```bat
cd C:\nginx
start nginx
```

To reload after config changes:

```bat
cd C:\nginx
nginx -s reload
```

To stop:

```bat
nginx -s quit
```

## 4. Cloudflare Tunnel

Keep the tunnel pointing at **http://localhost:8080**. No change needed if you left the AXM Demo site stopped and nginx is listening on 8080.

## 5. Test

- **https://axm.gmojsoski.com** → Platform  
- **https://superadmin.gmojsoski.com** → SuperAdmin  
- **https://vnhost.gmojsoski.com** → VnHost  

From this PC: `http://localhost:8080` with Host `axm.gmojsoski.com` (or use the hosts file and open the URL in a browser).

## Logs

- **C:\nginx\logs\error.log** – errors  
- **C:\nginx\logs\access.log** – access  

If a request fails, check `error.log` first.

---

## nginx won't start (troubleshooting)

**Uninstalling IIS does not stop nginx.** They are independent. If nginx doesn’t start, do this:

1. **Check the error log**  
   Open **C:\nginx\logs\error.log** (create the folder if needed). The last lines usually say why nginx failed (e.g. config error, port in use, missing file).

2. **Run from the right folder**  
   Always run from the nginx root (where `nginx.exe` is), e.g.:
   ```bat
   cd C:\nginx
   nginx
   ```
   If you run from another directory, paths like `logs/error.log` and `conf/axm.conf` can be wrong.

3. **Port 8080 in use**  
   In PowerShell:
   ```powershell
   netstat -an | findstr "8080"
   ```
   If something else is listening on 8080, stop that app or change `listen 8080` in `axm.conf` to another port (e.g. 8888) and point the Cloudflare tunnel at that port.

4. **Config / missing file**  
   - Ensure **axm.conf** is in **C:\nginx\conf\** and **nginx.conf** contains `include axm.conf;`.
   - The updated **nginx.conf** in this folder no longer uses `include mime.types` so it works even if that file is missing. Replace **C:\nginx\conf\nginx.conf** with this folder’s **nginx.conf** and try again.

5. **Test config without starting**  
   ```bat
   cd C:\nginx
   nginx -t
   ```
   This checks the config and prints any errors.
