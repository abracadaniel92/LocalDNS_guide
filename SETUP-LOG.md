# Local DNS + nginx setup – step log

Machine: this PC  
Date: 2025-03-04  
Local domains: **axm.local** (Platform), **superadmin.local** (SuperAdmin), **vnhost.local** (VnHost), **commnode.local** (CommNode)  
nginx port: **8080**

---

## Completed steps

| Step | Action | Result | Notes |
|------|--------|--------|--------|
| 1 | Config: add commnode.local to CoreDNS hosts.txt | OK | `coredns/hosts.txt`: axm, superadmin, vnhost, commnode |
| 2 | Config: add commnode.local server block to nginx axm.conf | OK | Proxies to http://127.0.0.1:50003 (change port if needed) |
| 3 | Config: set this machine IP in hosts.txt and axm.conf | OK | IP 10.10.10.68 (hosts.txt + server_name in axm.conf) |

---

## Pending / next steps

- [ ] Copy repo nginx configs into nginx install (or use C:\nginx with repo configs)
- [ ] Install CoreDNS (binary + Corefile + hosts.txt) to C:\coredns
- [ ] Start AXM bundle (ports 50000, 50001, 50002; CommNode on 50003 if used)
- [ ] Start CoreDNS as Administrator (port 53)
- [ ] Start nginx (port 8080)
- [ ] Set this PC DNS to 127.0.0.1 (or point clients to 10.10.10.68)
- [ ] Test: nslookup axm.local 127.0.0.1 → 10.10.10.68
- [ ] Test: http://axm.local:8080, http://superadmin.local:8080, http://vnhost.local:8080, http://commnode.local:8080

---

**Client-facing guide:** See **CLIENT-SETUP-GUIDE.md** for the full step-by-step documentation to share with the client (domains: axm.local, superadmin.local, vnhost.local, commnode.local; port 8080).

*Append new rows to "Completed steps" as you go.*
