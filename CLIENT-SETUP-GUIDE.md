# AXM local access – client setup guide (step-by-step)

**Purpose:** Access AXM (Platform, SuperAdmin, VnHost, CommNode) on the local network using friendly hostnames and port **8080**, without internet or public DNS.

**Local domains:**

| URL | Application | Backend port |
|-----|-------------|--------------|
| http://axm.local:8080 | Platform | 50003 |
| http://superadmin.local:8080 | SuperAdmin | 50004 |
| http://vnhost.local:8080 | VnHost | 50005 |
| http://commnode.local:8080 | CommNode | 60125 |

**Architecture (short):**

- **CoreDNS** (port 53): resolves axm.local, superadmin.local, vnhost.local, commnode.local → server IP.
- **nginx** (port 8080): reverse proxy by hostname to the correct backend (50000–50003).
- **AXM/CommNode apps**: run on this PC on 50000, 50001, 50002, 50003.

---

## Prerequisites

- Windows 10/11 or Windows Server.
- AXM bundle (and CommNode if used) installed and able to run on this PC.
- Administrator access (for CoreDNS on port 53 and for editing hosts if needed).
- This guide’s config files (from the `localdns_guide` repo).

---

## Step 1: Get the server’s LAN IP

1. Press **Win + R**, type `cmd`, press Enter.
2. Run: `ipconfig`
3. Find your active adapter (Ethernet or Wi-Fi) and note the **IPv4 Address** (e.g. `10.10.10.68` or `192.168.1.100`).  
   **Use this IP everywhere this guide says “SERVER_IP”.**

---

## Step 2: Prepare nginx

1. **Download nginx for Windows**  
   - https://nginx.org/en/download.html  
   - Get the **Windows** zip (e.g. mainline or stable).

2. **Extract** to a folder such as `C:\nginx\` so that `C:\nginx\nginx.exe` exists.

3. **Copy config files from this repo** into `C:\nginx\conf\`:
   - `localdns_guide\nginx\nginx.conf` → `C:\nginx\conf\nginx.conf`
   - `localdns_guide\nginx\axm.conf` → `C:\nginx\conf\axm.conf`

4. **Set your server IP in `axm.conf`:**
   - Open `C:\nginx\conf\axm.conf` in Notepad.
   - Find the line `server_name  10.10.10.68;` (or similar) in the “LAN access by IP” server block.
   - Replace that IP with **SERVER_IP**.
   - Save.

5. **Optional – CommNode port:**  
   If CommNode does not use port 60125, in `axm.conf` find the `commnode.local` server block and change `proxy_pass http://127.0.0.1:60125` to the correct port.

6. **Test config (in PowerShell):**
   ```powershell
   cd C:\nginx
   .\nginx.exe -t
   ```
   You should see: `syntax is ok` and `test is successful`.

---

## Step 3: Prepare CoreDNS

1. **Download CoreDNS for Windows**  
   - https://github.com/coredns/coredns/releases  
   - Get the Windows amd64 archive (e.g. `coredns_1.11.1_windows_amd64.tgz`).

2. **Extract** `coredns.exe` to a folder such as `C:\coredns\` so that `C:\coredns\coredns.exe` exists.

3. **Copy config files from this repo** into `C:\coredns\`:
   - `localdns_guide\coredns\Corefile` → `C:\coredns\Corefile`
   - `localdns_guide\coredns\hosts.txt` → `C:\coredns\hosts.txt`

4. **Set your server IP in `hosts.txt`:**
   - Open `C:\coredns\hosts.txt`.
   - Replace the IP on the single line with **SERVER_IP**.  
     The line should look like:  
     `SERVER_IP axm.local superadmin.local vnhost.local commnode.local`
   - Save.

---

## Step 4: Start the AXM bundle (and CommNode)

1. Start **Platform** (listening on port **50003**).
2. Start **SuperAdmin** (port **50004**).
3. Start **VnHost** if used (port **50005**).
4. Start **CommNode** if used (port **60125**; set in bundle/data.json and `axm.conf` if different).

Verify in the browser (on this PC):

- http://localhost:50003 (Platform)
- http://localhost:50004 (SuperAdmin)
- http://localhost:50005 (VnHost) if used
- http://localhost:60125 (CommNode) if used

Leave these running.

---

## Step 5: Start CoreDNS (as Administrator)

1. Right-click **PowerShell** → **Run as administrator**.
2. Run:
   ```powershell
   cd C:\coredns
   .\coredns.exe -conf Corefile
   ```
3. You should see something like:
   ```text
   .:53
   CoreDNS-1.x.x
   ...
   ```
4. Leave this window open. CoreDNS runs in the foreground.

If you see “bind: permission denied”, ensure PowerShell is run as Administrator (port 53 needs it).  
If you see “address already in use”, another service is using port 53; stop it or use a different port in the Corefile (and adjust client DNS accordingly).

---

## Step 6: Start nginx

1. Open a **new** PowerShell window (normal user is fine).
2. Run:
   ```powershell
   cd C:\nginx
   .\nginx.exe
   ```
3. Check that nginx is listening on 8080:
   ```powershell
   netstat -ano | findstr "8080"
   ```
   You should see a line with `LISTENING` and port 8080.

If nginx does not start, check `C:\nginx\logs\error.log` and run `.\nginx.exe -t` again.

---

## Step 7: Point this PC’s DNS to itself (so it uses CoreDNS)

1. Press **Win + R**, type `ncpa.cpl`, press Enter.
2. Right-click your **active network adapter** (Ethernet or Wi-Fi) → **Properties**.
3. Select **Internet Protocol Version 4 (TCP/IPv4)** → **Properties**.
4. Select **Use the following DNS server addresses**:
   - Preferred DNS server: **127.0.0.1**
   - Alternate (optional): **8.8.8.8**
5. Click OK, then OK again.

---

## Step 8: Test DNS

In PowerShell:

```powershell
nslookup axm.local 127.0.0.1
nslookup superadmin.local 127.0.0.1
nslookup vnhost.local 127.0.0.1
nslookup commnode.local 127.0.0.1
```

Each should return **SERVER_IP**.

---

## Step 9: Test in the browser (on this PC)

Open:

- http://axm.local:8080 → Platform  
- http://superadmin.local:8080 → SuperAdmin  
- http://vnhost.local:8080 → VnHost  
- http://commnode.local:8080 → CommNode  

If you see “This site can’t be reached” or DNS errors, re-check Step 7 and 8.  
If you see nginx 502/504, the corresponding backend (50000–50003) may not be running; check Step 4.

---

## Step 10: Other devices on the LAN (optional)

So other PCs/phones can use the same hostnames:

**Option A – DNS (recommended)**  
On each device (or in the router’s DHCP settings), set DNS to **SERVER_IP**. Then they can use:

- http://axm.local:8080  
- http://superadmin.local:8080  
- http://vnhost.local:8080  
- http://commnode.local:8080  

**Option B – Hosts file (per device)**  
On each PC, edit the hosts file (as Administrator) and add one line:

```text
SERVER_IP   axm.local superadmin.local vnhost.local commnode.local
```

- Windows: `C:\Windows\System32\drivers\etc\hosts`  
- Mac/Linux: `/etc/hosts`

Then use the same URLs as above (with `:8080`).

---

## Stopping services

- **CoreDNS:** In its window, press **Ctrl+C**.
- **nginx:** In PowerShell:
  ```powershell
  cd C:\nginx
  .\nginx.exe -s quit
  ```
  If that fails: `taskkill /IM nginx.exe /F`

After changing nginx config, do a full stop (`taskkill /IM nginx.exe /F`) then start again with `.\nginx.exe`.

---

## Running as Windows services (optional)

For automatic start at boot, install CoreDNS and nginx as services (e.g. with NSSM). See the “Running as Windows services” section in `COREDNS-NGINX-LOCAL-ACCESS.md` in this repo.

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| “This site can’t be reached” / DNS_PROBE | CoreDNS running? DNS on this PC set to 127.0.0.1? Run `nslookup axm.local 127.0.0.1`. |
| nslookup works, browser does not | Turn off browser “Secure DNS” (e.g. Chrome → Settings → Privacy and security → Use secure DNS → Off). |
| 502 Bad Gateway from nginx | Backend for that host not running (50003/50004/50005/60125). Start the AXM/CommNode app. |
| nginx won’t start | Port 8080 in use? Run `.\nginx.exe -t` and check `C:\nginx\logs\error.log`. |
| CoreDNS “permission denied” | Run PowerShell as Administrator. |
| CoreDNS “address already in use” | Another DNS service is using port 53; stop it or use another port in Corefile. |

---

## Summary checklist

- [ ] SERVER_IP noted from `ipconfig`
- [ ] nginx extracted to `C:\nginx\`, configs copied, `axm.conf` IP and CommNode port updated, `nginx -t` OK
- [ ] CoreDNS extracted to `C:\coredns\`, configs copied, `hosts.txt` IP updated
- [ ] AXM (and CommNode) running on 50003, 50004, 50005, 60125
- [ ] CoreDNS started as Administrator
- [ ] nginx started; port 8080 listening
- [ ] This PC DNS = 127.0.0.1
- [ ] nslookup for axm.local, superadmin.local, vnhost.local, commnode.local returns SERVER_IP
- [ ] http://axm.local:8080, http://superadmin.local:8080, http://vnhost.local:8080, http://commnode.local:8080 work in browser

**Domains:** axm.local (Platform), superadmin.local (SuperAdmin), vnhost.local (VnHost), commnode.local (CommNode).  
**Port:** 8080 for all URLs.
