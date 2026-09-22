# Traefik — the host that is NOT the app host

**Traefik and the Healthee stack run on two different machines, on a shared private
network.** That single fact decides most of what follows, so it is first.

Traefik's Docker provider reads labels from **its own** daemon's socket. It cannot
see the Healthee containers, so there are no `traefik.*` labels anywhere in
`infra/dockge/compose.yaml`, and adding some would do nothing at all — the stack
would come up green and never be routed.

```
 [ internet ] ──TLS──> [ TRAEFIK HOST ] ──plain http, private net──> [ HEALTHEE BOX ]
                        /etc/traefik/dynamic/healthee.yml             10.0.0.5:8765
                                                                      (Dockge stack)
```

| On the Traefik host | On the Healthee box |
|---|---|
| router, service, all four middlewares (`healthee.yml.template`) | the stack (`infra/dockge/compose.yaml`) |
| entrypoints, cert resolver, forwarded-header trust, access log | `HEALTHEE_BIND_ADDR` — the private ip it publishes on |
| TLS termination | nothing TLS-related at all |

`apps/server/tests/test_edge_traefik.py` asserts the template and asserts its
numbers still agree with the nginx vhost it replaces. **This file is the
remainder** — what lives in *static* config, which this repository cannot ship or
test. Work through it once when you stand the stack up, and again if you put a CDN
in front.

> Why a checklist and not a test: Traefik's static config is a file on a machine
> this repo has never seen. Saying so is better than a test that checks a file we
> ship and implies coverage we do not have.

---

## 0. Install the dynamic config

On the Traefik host, the static config needs a file provider:

```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true          # reloads on save; no restart, no dropped connections
```

Then render ours into it, from a checkout on either machine:

```bash
# on the Traefik host, values passed inline:
PUBLIC_HOST=api.example.com HEALTHEE_BIND_ADDR=10.0.0.5 \
  infra/traefik/render-dynamic.sh --install

# or render on the Healthee box, where .env already has both, and pipe it across:
infra/traefik/render-dynamic.sh | ssh traefik-host \
  'sudo tee /etc/traefik/dynamic/healthee.yml >/dev/null'
```

Confirm Traefik picked it up:

```bash
curl -s http://127.0.0.1:8080/api/http/routers/healthee@file | head
```

⚠ **Re-render whenever `HEALTHEE_BIND_ADDR` or `PUBLIC_HOST` changes.** The two
machines each hold half of this and nothing reconciles them; a stale backend address
is a 502 with a perfectly healthy stack behind it.

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

The `certResolver` named in `healthee.yml.template` (`letsencrypt`) must exist in
your static config. Edit the template if yours is called something else.

**DNS for `PUBLIC_HOST` must resolve to the TRAEFIK host — not to the Healthee
box** — and must do so *before* the first request. ACME HTTP-01 validates by being
reached, so a record pointing at the wrong machine of the two fails validation and
leaves the router serving Traefik's default self-signed certificate. The symptom on
the phone is a TLS error, not a 404, which sends you looking at the wrong box.

The Healthee box needs no DNS record at all, and should not have a public one.

---

## 6. Noted, and deliberately not changed: `--forwarded-allow-ips "*"`

The api's uvicorn runs with `--proxy-headers --forwarded-allow-ips "*"`
(`infra/docker/Dockerfile.server`). That was unambiguous when nginx on loopback was
the only possible caller. Now **any machine on the private network** can reach
`10.0.0.5:8765` directly and forge `X-Forwarded-For`.

**Left as is, because the server reads no client IP** — there is no
`request.client`, no `X-Forwarded-For` consumer and no IP-based logic anywhere in
`apps/server/src/` (grepped, not assumed). So a forged value has nothing to
influence: rate limiting is the edge's job and auth is bearer-JWT only.

Revisit this the moment any per-IP behaviour moves into the app — and note that in
this topology the rate limiter's `depth` (§1) is the thing that would inherit the
problem, because it is the one component that does decide based on an IP.

---

## 7. ⛔ The hop between the two machines is UNENCRYPTED

Traefik terminates TLS and then talks plain HTTP to `10.0.0.5:8765`. Everything that
crosses that link is in the clear on your private network, and for this application
that includes:

- **Supabase access JWTs** on every single request — a bearer token is all the API
  checks, so anyone who can read one can impersonate that owner until it expires;
- **the health data itself**, in both directions;
- **basemap tile paths**, which are street corners (see §2).

This did not exist as a risk when nginx and the app shared a kernel and talked over
loopback. It is the one thing about this topology that differs *in kind*, not just
in configuration. Decide deliberately which of these applies to you:

**a. The private network is genuinely isolated** — a cloud provider VPC scoped to
your project (Hetzner private networks, DO VPC, AWS security-grouped subnet) with no
other tenants and no other machines you do not control. Plain HTTP is a reasonable
call. **Confirm it is actually isolated**, rather than a flat LAN that merely feels
private.

**b. It is a shared or untrusted LAN, or it crosses a datacentre boundary** — then
plain HTTP is not acceptable for bearer tokens and health records. Put an encrypted
overlay under it (WireGuard or Tailscale) and point `HEALTHEE_BIND_ADDR` at the
overlay address — a `100.x.y.z` tailscale0 address rather than the LAN one. Nothing
else in the setup changes; the render script and the stack both just take the new
address.

Whichever you pick, the port must never be reachable from outside that network:

```bash
# from a THIRD machine, off the private network — this MUST fail:
curl --max-time 5 http://<healthee-box-public-ip>:8765/healthz
```

⚠ `ufw deny 8765` does **not** achieve this. Docker inserts its own iptables rules
ahead of ufw's chain, so a published port stays reachable through a ufw DENY. The
bind address in `HEALTHEE_BIND_ADDR` is the control that actually works.
