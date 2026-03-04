# nginx vs IIS: forwarded headers (same behaviour)

When using IIS with URL Rewrite + ARR, the doc says to set these **Server Variables** (per rule or in the Forward Proxy Headers rule):

| IIS Server Variable      | Value in IIS        | Purpose |
|--------------------------|---------------------|--------|
| **HTTP_X_FORWARDED_HOST**  | `{HTTP_HOST}`       | Original host the client used (e.g. axm.local:8080) |
| **HTTP_X_FORWARDED_PROTO** | `https` (or `http`) | Scheme the client used |
| **HTTP_X_FORWARDED_FOR**   | `{REMOTE_ADDR}`     | Client IP address |

IIS then sends these as HTTP headers to the backend (e.g. `X-Forwarded-Host`, `X-Forwarded-Proto`, `X-Forwarded-For`).

---

## nginx equivalent (what we use)

In **nginx** we do the same thing in `axm.conf` with `proxy_set_header`:

| IIS (Name → Value)           | nginx directive |
|-----------------------------|------------------|
| **HTTP_X_FORWARDED_HOST** → `{HTTP_HOST}`   | `proxy_set_header X-Forwarded-Host $host:$server_port;` |
| **HTTP_X_FORWARDED_PROTO** → `https`       | `proxy_set_header X-Forwarded-Proto $scheme;`          |
| **HTTP_X_FORWARDED_FOR** → `{REMOTE_ADDR}`  | `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` |

- **$host** = hostname from the request (like IIS `{HTTP_HOST}` without port). We add **$server_port** so the backend gets e.g. `axm.local:8080`.
- **$scheme** = http or https (so we don’t hardcode `https`; use `https` in IIS when the client hits IIS over HTTPS).
- **$proxy_add_x_forwarded_for** = appends the client IP (like `{REMOTE_ADDR}`); preserves any existing `X-Forwarded-For` from upstream.

So the backend receives the same forwarded information whether it’s behind **IIS** (with those server variables) or **nginx** (with these headers). No extra nginx config is needed beyond what’s already in `axm.conf`.
