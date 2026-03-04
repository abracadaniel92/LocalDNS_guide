# Access AXM from a laptop on the same network

To open **http://axm.local:8080** (and superadmin.local, vnhost.local, commnode.local) from another PC on the same LAN, you need **two** things.

---

## 1. Laptop must resolve axm.local to the server IP

The laptop has no idea what "axm.local" is unless you tell it.

**Option A – Hosts file on the laptop (simplest)**

1. On the **laptop**, get the **AXM server’s LAN IP** (on the PC that runs AXM, run `ipconfig` and note the IPv4 address, e.g. **10.10.10.68**).
2. On the **laptop**, edit the hosts file **as Administrator**:
   - **Windows:** `C:\Windows\System32\drivers\etc\hosts`
   - **Mac:** `/etc/hosts`
   - **Linux:** `/etc/hosts`
3. Add **one line** (use the real server IP, not 10.10.10.68 if yours is different):

   ```
   10.10.10.68    axm.local superadmin.local vnhost.local commnode.local
   ```

4. Save. Then on the laptop try **http://axm.local:8080**.

**Option B – Use the server as DNS (CoreDNS on server)**

1. On the **AXM server**: run CoreDNS (as Administrator) so it listens on port 53 and resolves axm.local, superadmin.local, etc. to the server IP (see `COREDNS-NGINX-LOCAL-ACCESS.md`).
2. On the **laptop**: set its DNS to the **server’s IP** (e.g. 10.10.10.68).
   - **Windows:** `ncpa.cpl` → adapter → IPv4 → Preferred DNS server = **10.10.10.68**
   - **Mac:** System Preferences → Network → DNS = **10.10.10.68**
3. Then the laptop will resolve axm.local via the server. Use **http://axm.local:8080**.

---

## 2. Server must allow inbound traffic on port 8080

The PC that runs AXM and nginx must accept connections from the LAN on port **8080**.

**Windows Firewall on the AXM server**

1. On the **AXM server** (the PC running nginx and AXM), open **Windows Defender Firewall with Advanced Security** (or run `wf.msc`).
2. **Inbound Rules** → **New Rule…**
3. **Port** → Next → **TCP**, **Specific local ports:** `8080` → Next.
4. **Allow the connection** → Next.
5. Check **Domain** and **Private** (and **Public** if the laptop is on a public profile) → Next.
6. Name: e.g. **AXM nginx 8080** → Finish.

Or in an **Administrator** PowerShell on the server:

```powershell
New-NetFirewallRule -DisplayName "AXM nginx 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private,Domain
```

Then from the laptop, **http://axm.local:8080** should load (after step 1 is done).

---

## Quick checklist (laptop can’t access axm.local)

| Check | Action |
|--------|--------|
| Laptop resolves axm.local | Add server IP + axm.local (and other .local names) to the **laptop’s hosts file**, or set laptop DNS to server IP and run **CoreDNS** on the server. |
| Server allows port 8080 | On the **AXM server**, add a **Windows Firewall** inbound rule allowing **TCP 8080** for Private/Domain. |
| nginx listening on all interfaces | nginx should listen on `0.0.0.0:8080` (default). Confirm with `netstat -ano | findstr "8080"` on the server. |
| Same network | Laptop and server on the same subnet (e.g. both 10.10.10.x) and no VPN/router blocking LAN traffic. |

---

## Test from the laptop

- **DNS:** `ping axm.local` → should show the server IP and get replies.
- **Browser:** **http://axm.local:8080** → should open the AXM Platform (or a login page).

If ping works but the browser doesn’t, firewall on the server is the likely cause (open TCP 8080 as above).

---

## Still can’t access? Run these checks

**On the AXM server (the PC that runs nginx/AXM):**

1. Confirm nginx listens on all interfaces (not just localhost):
   ```powershell
   netstat -ano | findstr ":8080"
   ```
   You should see `0.0.0.0:8080` or `[::]:8080` (not only `127.0.0.1:8080`). If you only see 127.0.0.1, nginx is not accepting LAN connections; fix the nginx config so it has `listen 8080;` without a specific IP.

2. Note the server’s LAN IP (e.g. 10.10.10.68):
   ```powershell
   ipconfig | findstr "IPv4"
   ```

3. Confirm the firewall rule exists:
   ```powershell
   Get-NetFirewallRule -DisplayName "AXM nginx 8080" | Select-Object DisplayName, Enabled, Direction, Action
   ```

**On the laptop (the other machine):**

1. **Hosts file:** Open `C:\Windows\System32\drivers\etc\hosts` as Administrator. You must have a line like (use the **server’s** IP from step 2 above):
   ```
   10.10.10.68    axm.local superadmin.local vnhost.local commnode.local
   ```
   Save and close. If the line is missing or has the wrong IP, fix it.

2. **Test DNS:** In PowerShell or CMD:
   ```powershell
   ping axm.local
   ```
   - If it says “Ping request could not find host axm.local” → hosts file not applied (wrong file, not saved, or browser using Secure DNS). Fix hosts; in Chrome turn off Settings → Privacy and security → Use secure DNS.
   - If it shows the server IP and replies → DNS is OK, go to step 3.

3. **Test port 8080** (replace with the server’s real IP if different):
   ```powershell
   Test-NetConnection -ComputerName 10.10.10.68 -Port 8080
   ```
   - If `TcpTestSucceeded : True` → network and firewall are OK; try http://axm.local:8080 in the browser (use **http**, not https).
   - If `TcpTestSucceeded : False` → firewall on server, or different subnet/VPN. Check server firewall rule and network.

4. **Browser:** Use **http://axm.local:8080** (not https). If the laptop uses Chrome “Secure DNS”, turn it off so the hosts file is used.
