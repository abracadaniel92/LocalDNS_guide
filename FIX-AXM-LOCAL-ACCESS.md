# Fix: Can't access axm.local:8080

## What was wrong

1. **DNS** – `axm.local` didn't resolve. CoreDNS wasn't running (port 53), and the Windows **hosts** file had no entry for `axm.local`.
2. **nginx** – The nginx on port 8080 (e.g. from Downloads) didn't have the AXM proxy config, so even with DNS fixed it wouldn't route `axm.local` to the Platform backend.

## What was fixed (config)

- **AXM proxy config** was added to your nginx:  
  `C:\Users\Simonsvoss\Downloads\nginx-1.29.5\nginx-1.29.5\conf\axm.conf`  
  and included from `nginx.conf`. So nginx now routes:
  - `axm.local` → 50003 (Platform)
  - `superadmin.local` → 50004 (SuperAdmin)
  - `vnhost.local` → 50005 (VnHost)
  - `commnode.local` → 60125 (CommNode)

## What you must do (one-time)

### 1. Add hosts file entries (run as Administrator)

So that `axm.local` (and the others) resolve on this PC **without** CoreDNS:

1. Open **Notepad as Administrator** (right‑click Notepad → Run as administrator).
2. File → Open → go to:  
   `C:\Windows\System32\drivers\etc\hosts`  
   (set "Text Documents (*.txt)" to **All Files** so you see `hosts`).
3. At the **end** of the file, add this line (one line):

   ```
   127.0.0.1       axm.local superadmin.local vnhost.local commnode.local
   ```

4. Save and close.

### 2. Restart nginx (load the new config)

In PowerShell:

```powershell
taskkill /IM nginx.exe /F
cd "C:\Users\Simonsvoss\Downloads\nginx-1.29.5\nginx-1.29.5"
.\nginx.exe
```

### 3. Test

- In the browser open: **http://axm.local:8080**
- You should get the AXM Platform (backend on port 50003).

Also try:

- http://superadmin.local:8080  
- http://vnhost.local:8080  
- http://commnode.local:8080  

(Each only works if the matching app is running on its port.)

## Optional: use CoreDNS later

If you want other devices to use `axm.local` without editing their hosts file, run CoreDNS (as Administrator) and point their DNS to this PC's IP. See `COREDNS-NGINX-LOCAL-ACCESS.md`.
