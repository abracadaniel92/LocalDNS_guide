# AXM IIS reverse proxy – checklist vs official doc

Comparison of our setup with the **IIS Reverse Proxy Configuration for AXM** document. Our hostnames are **axm**, **superadmin**, **vnhost** under **gmojsoski.com** (doc uses app.axm.demo, admin.axm.demo, vnhost.axm.demo).

---

## Already in our web.config

| Doc requirement | Our setup |
|----------------|-----------|
| **allowedServerVariables** for X-Forwarded-* | ✓ `HTTP_X_FORWARDED_HOST`, `HTTP_X_FORWARDED_PROTO`, `HTTP_X_FORWARDED_FOR` in `<allowedServerVariables>` |
| **Forward Proxy Headers** rule (pattern `.*`, action None, set all 3 server variables) | ✓ First rule |
| **Host-based proxy rules** (match Host, rewrite to backend, appendQueryString) | ✓ axm → 50000, superadmin → 50001, vnhost → 50002 |
| **Server variables in proxy rules** (doc “alternative”: set in each host-based rule) | ✓ Added in each of the three proxy rules so backend always gets X-Forwarded-* |
| **webSocket enabled="true"** | ✓ |
| **Backend ports** | Platform 50000, SuperAdmin 50001, VnHost 50002 (doc example ports differ; ours match your AXM) |

We use **HTTP** to the backends (http://127.0.0.1:50000, 50001) to avoid ARR/backend SSL issues; doc examples use HTTPS. VnHost is still **HTTPS** to 50002.

---

## Do in IIS Manager (not in web.config)

### 1. ARR: enable proxy (you did this)
- Server node → **Application Request Routing** → **Server Proxy Settings** → **Enable proxy** → Apply.

### 2. ARR: disable “Reverse rewrite host in response headers” (doc requirement)
- Server node (top of tree) → **Application Request Routing** → **Server Proxy Settings**.
- Find **“Reverse rewrite host in response headers”** (or similar).
- Set it to **disabled** / **unchecked** and **Apply**.

This keeps response headers aligned with the external hostnames (axm.gmojsoski.com, etc.) instead of the backend Host header.

### 3. Server Variables in IIS (only if our allowedServerVariables in web.config are ignored)
- Site **AXM Demo** → **URL Rewrite** → **View Server Variables** (right-hand Actions).
- If **HTTP_X_FORWARDED_HOST**, **HTTP_X_FORWARDED_PROTO**, **HTTP_X_FORWARDED_FOR** are not listed, click **Add…** for each and save.

Many setups work with only the `<allowedServerVariables>` in web.config; use this step if the backend does not receive X-Forwarded-* headers.

---

## Differences from the doc (by design)

| Topic | Doc | Our setup | Reason |
|-------|-----|-----------|--------|
| **Hostnames** | app.axm.demo, admin.axm.demo | axm.gmojsoski.com, superadmin.gmojsoski.com | Your domain and single-label for free SSL. |
| **IIS bindings** | HTTPS :443 with cert per hostname | HTTP :8080 only | Cloudflare Tunnel terminates SSL and sends HTTP to localhost:8080. |
| **Backend URL** | https://localhost:5xxx | http://127.0.0.1:50000, 50001 | Avoids backend SSL validation in ARR; your backends accept HTTP on these ports. |

---

## Summary

- **web.config**: Matches the doc (allowed server variables, Forward Proxy Headers rule, host-based rules with server variables, WebSocket, query string). No further web.config changes needed for the doc.
- **IIS Manager**: Confirm **Enable proxy** and **disable “Reverse rewrite host in response headers”** at server level; optionally add the three server variables via “View Server Variables” if the backend does not see X-Forwarded-* headers.

After that, copy the updated **web.config** to **C:\inetpub\axm-demo\** and recycle the AXM Demo app pool (or restart the site).
