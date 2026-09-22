# Traefik — the parts that are NOT in our compose file

`infra/dockge/compose.yaml` carries everything Traefik can be told with container
labels: the router, the rate limit, the connection cap, the body cap, the security
headers. `apps/server/tests/test_edge_traefik.py` asserts all of it, and asserts that
it still agrees with the nginx vhost it replaces.

**This file is the remainder** — the settings that live in *your* Traefik's static
configuration, which this repository does not own and cannot test. Two of them are
live-fire issues rather than tidiness. Work through it once when you stand the stack
up, and again if you ever put a CDN in front.

> Why a checklist and not a test: Traefik's static config is a file on your box (or
> your Traefik stack's own compose). Nothing here can read it. Saying so is better
> than a test that checks a file we ship and implies coverage we do not have.

---

## 0. The network must exist before the stack starts

```bash
docker network create proxy       # must match TRAEFIK_NETWORK in .env
```

The stack declares it `external: true`, so compose **refuses to start** rather than
quietly creating a second, unrouted network with the same name. That refusal is the
feature; if you see it, the network is missing, not misnamed.

Traefik itself must also be attached to this network.

---

## 1. ⛔ Trust your edge's IPs, or the rate limiter protects nobody

**The failure:** the limiter buckets by client IP. Behind Cloudflare (or any proxy),
the TCP peer is *the CDN*, so **every visitor on earth shares one bucket** — one
owner's sync drain returns 429 to everyone else. Unthrottled is bad; globally
self-throttling is worse, and it looks like an outage with no error in our logs.

Two settings, and **both** are required — either alone does nothing:

**a. Trust the header, in Traefik's static config.** Without this Traefik discards
the incoming `X-Forwarded-For`, so there is nothing for step (b) to read:

```yaml
entryPoints:
  websecure:
    address: ":443"
    forwardedHeaders:
      trustedIPs:
        # Cloudflare — refresh from https://www.cloudflare.com/ips/
        - 173.245.48.0/20
        - 103.21.244.0/22
        - 103.22.200.0/22
        - 103.31.4.0/22
        - 141.101.64.0/18
        - 108.162.192.0/18
        - 190.93.240.0/20
        - 188.114.96.0/20
        - 197.234.240.0/22
        - 198.41.128.0/17
        - 162.158.0.0/15
        - 104.16.0.0/13
        - 104.24.0.0/14
        - 172.64.0.0/13
        - 131.0.72.0/22
```

**b. Tell the middlewares how deep to look**, in the stack's `.env`:

```ini
TRAEFIK_IP_DEPTH=1      # behind Cloudflare / any single proxy
TRAEFIK_IP_DEPTH=0      # Traefik is directly internet-facing (the default)
```

`depth` counts from the **right** of `X-Forwarded-For`. One proxy in front ⇒ `1`.

**Verify it, don't assume it.** From two different external IPs, hammer `/healthz`
past 20 r/s and confirm only the offender gets 429s:

```bash
for i in $(seq 1 200); do curl -s -o /dev/null -w '%{http_code}\n' \
  https://<your-host>/healthz; done | sort | uniq -c
```

---

## 2. ⛔ Keep request PATHS out of the access log

**This is a privacy property of the product, not a logging preference.**

The app never talks to a tile provider; it asks *our* server, which fetches and
caches. That is the whole reason the tile proxy exists — so that the streets an owner
runs on are not assembled in a third party's logs. But
`/api/map/tiles/17/19134/12440` **is** a street corner, and a list of them beside
timestamps is a location history. Writing it into Traefik's access log just moves the
file to our own disk.

The retired nginx vhost handled this with `access_log off` inside
`location /api/map/tiles/`. **Traefik cannot disable access logging per-router.** So
pick one:

**Option A — no access log** (simplest, and what the deployment assumes):

```yaml
# Simply do not configure `accessLog:` at all.
```

**Option B — log, but drop the path globally:**

```yaml
accessLog:
  filePath: /var/log/traefik/access.log
  fields:
    names:
      RequestPath: drop
```

`drop` removes the field entirely. Note this costs you the path on *every* route, not
just tiles — that is the trade, and it is the honest one to make.

⚠ If you add any log shipper, dashboard or analytics in front, check it the same way.
The app already suppresses these paths in uvicorn's own access log
(`core/logging.silence_access_log_for`); the edge is the remaining hole.

---

## 3. Timeouts — verify against the coach, which is the long pole

Most requests finish in milliseconds. The coach does not: `GATHERING_DEADLINE_S=150`
plus the answer attempts, against an app that waits 360 s.

The relevant knobs, all static config:

| Setting | Scope | What it bounds |
|---|---|---|
| `entryPoints.<ep>.transport.respondingTimeouts.readTimeout` | entrypoint | reading the request, **body included** — matters for an 8 MB ingest on a slow phone |
| `entryPoints.<ep>.transport.respondingTimeouts.writeTimeout` | entrypoint | writing the response |
| `entryPoints.<ep>.transport.respondingTimeouts.idleTimeout` | entrypoint | idle keep-alive connections |
| `serversTransport.forwardingTimeouts.responseHeaderTimeout` | global | waiting for the app's response headers |

The coach **streams its draft**, so response headers arrive early and
`responseHeaderTimeout` is not the binding constraint — but `writeTimeout` spans the
whole streamed response and is. Do not leave these to memory: send one real coach
question through the edge and confirm it completes, rather than reading defaults off
a docs page.

---

## 4. HTTP → HTTPS

Handled at the entrypoint, not by our labels (our router is bound to `websecure`
only):

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
```

---

## 5. Certificates

`TRAEFIK_CERTRESOLVER` in the stack's `.env` must name a resolver that exists in your
static config. **DNS for `PUBLIC_HOST` must already resolve to this box before the
first request** — ACME HTTP-01 validates by being reached, and a resolver that fails
leaves a router serving Traefik's default self-signed certificate. The symptom on the
phone is a TLS error, not a 404.

---

## 6. Noted, and deliberately not changed: `--forwarded-allow-ips "*"`

The api's uvicorn runs with `--proxy-headers --forwarded-allow-ips "*"`
(`infra/docker/Dockerfile.server`). That was unambiguous when nginx on loopback was
the only possible caller; on a shared Traefik network, any other container on
`proxy` can reach `healthee-api:8765` directly and forge `X-Forwarded-For`.

**Left as is, because the server reads no client IP** — there is no
`request.client`, no `X-Forwarded-For` consumer and no IP-based logic anywhere in
`apps/server/src/`. So the forged value has nothing to influence: rate limiting is
the edge's job, and auth is Bearer-JWT only.

Revisit this the moment any per-IP behaviour moves into the app.
