# AXM bundle exploration

Summary of **C:\Users\User1\Desktop\New folder (2)** (read-only exploration).

---

## Top-level structure

| Item | Purpose |
|------|--------|
| **data.json** | Bundle config: edition (Plus), environment (Development), app list, ports, paths, OpenID clients and redirect URIs. Launcher reads this to start apps. |
| **backend\** | All five backend apps (platform, superadmin, commnode, virtualcommnode, vnhost). |
| **logs\** | Per-app log folders (axm.platform, axm.superadmin, etc.). |

The launcher executable is **not** in this folder; it is separate and uses `data.json` to find and start each app.

---

## Backend apps (ports and main config)

| App | Port | Main config | Entry / web |
|-----|------|-------------|-------------|
| **axm.superadmin** | 50001 | appsettings.json, appsettings.Development.json | API + wwwroot\web\environments\environment.json |
| **axm.platform** | 50000 | appsettings.json, appsettings.Plus.json, appsettings.Development.json | wwwroot (Angular), Kestrel in Plus/Development |
| **axm.vnhost** | 50002 | appsettings.json, appsettings.Development.json, appcfg/msgcfg.xml | VNHostSvr; install_VNHostSvr.bat / uninstall |
| **axm.commnode** | 60123 | appsettings.json, appsettings.Development.json | Content\CommNode.URL → localhost:60123 |
| **axm.virtualcommnode** | 60124 | appsettings.json, appsettings.Development.json | Content\CommNode.URL → localhost:60124 |

Startup order in `data.json`: SuperAdmin (100) → Platform (200) → CommNode, VirtualCommNode, VnHost (300). Dependencies: Platform and others depend on SuperAdmin; CommNode/VirtualCommNode/VnHost depend on Platform and SuperAdmin.

---

## Where ports and URLs are set

- **data.json** (root): `applications[].configuration.port`, `openIdApplications` (redirectUris). Single place for bundle-level ports and OpenID.
- **Per-app:**  
  - **Kestrel / BaseUrl:** each app’s `appsettings.json` and `appsettings.Development.json` (and variant: Plus, Classic, Lite, etc. for Platform).  
  - **Front-end API/auth URLs:**  
    - Platform: `backend\axm.platform\wwwroot\environments\environment.json` (apiUrl, authApiUrl, apiVnHost).  
    - SuperAdmin: `backend\axm.superadmin\wwwroot\web\environments\environment.json` (apiUrl, authApiUrl).

Authority (auth server) is effectively **SuperAdmin** (50001); Platform and others point to it for OpenID. Platform is the main web app (50000); VnHost is 50002.

---

## Scripts and docs

- **backend\axm.vnhost\install_VNHostSvr.bat** – install VnHost as Windows service (delayed-auto).  
- **backend\axm.vnhost\uninstall_VNHostSvr.bat** – unregister VNHostSvr.  
- **backend\axm.platform\APPSETTINGS-README.txt** – appsettings layering and where to set CORS/Authority/SUP for public URLs.

No installer (.msi) was found inside this bundle folder.

---

## Folder tree (summary)

```
New folder (2)/
├── data.json
├── backend/
│   ├── axm.platform/    # appsettings.*, wwwroot, confgen, netcfg/msgcfg/appcfg.xml
│   ├── axm.superadmin/  # appsettings.*, wwwroot\web\environments\environment.json
│   ├── axm.commnode/    # appsettings.*, Content\CommNode.URL, confgen
│   ├── axm.virtualcommnode/
│   └── axm.vnhost/      # appsettings.*, appcfg/msgcfg, install/uninstall .bat
└── logs/
    ├── axm.platform/
    ├── axm.superadmin/
    ├── axm.commnode/
    ├── axm.virtualcommnode/
    └── axm.vnhost/
```

---

## For reverse proxy / tunnel (axm.gmojsoski.com)

- **Public hostnames:** axm → 50000 (Platform), superadmin → 50001 (SuperAdmin), vnhost → 50002 (VnHost).
- **Config to align:**  
  - `data.json`: redirectUris for axm.webapp and axm.superadmin.webapp (public URLs).  
  - Platform: appsettings (CORS, Authority, SUP BaseUrl) and optionally wwwroot\environments\environment.json if the SPA calls APIs by URL.  
  - SuperAdmin: appsettings (CORS, OpenIddict redirect URIs).  
  - All of these have been updated in previous steps for axm.gmojsoski.com and superadmin.gmojsoski.com.
