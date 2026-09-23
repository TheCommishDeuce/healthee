# Healthee on Dockge, behind Traefik on another machine

**Two machines.** Traefik terminates TLS on one; the Dockge stack runs on the other;
they talk over your private network. Nothing about the app is on the public internet.

```
 [ internet ] ──TLS──> [ TRAEFIK HOST ] ──http, private net──> [ HEALTHEE BOX ]
                        DNS points here                         10.0.0.5:8765
                        /etc/traefik/dynamic/healthee.yml        Dockge stack
                                                                 no public DNS
```

⛔ **There are no `traefik.*` labels in this stack, and adding some would do
nothing.** Traefik's Docker provider reads labels from its own daemon's socket, so
it cannot see containers on another machine. The router, the service and all four
middlewares live in a file on the Traefik host instead —
`infra/traefik/healthee.yml.template`, rendered by `render-dynamic.sh`.

The stack: `db` (TimescaleDB) · `preflight` (one-shot gate) · `api` · `scheduler`.
Images come from GHCR, published by CI — nothing is built on either machine.

| What | Where it goes |
|---|---|
| `infra/dockge/compose.yaml` | Healthee box → `/opt/stacks/healthee/compose.yaml` |
| `infra/dockge/.env.example` | Healthee box → `/opt/stacks/healthee/.env` |
| `infra/dockge/deploy.sh` | Healthee box, run from the repo checkout |
| `infra/traefik/healthee.yml.template` | **Traefik host** → `/etc/traefik/dynamic/healthee.yml` |

---

## Setup, machine by machine

### On the HEALTHEE box

**1. Find its private IP.** This is the single most important value in the setup:

```bash
ip -4 addr | grep -v 127.0.0.1
```

Take the address on the **private** interface — Hetzner `ens10`, DO `eth1`, or a
`100.x` address on `tailscale0`. **Not** `eth0`'s public address.

**2. Clone the repo** (for `deploy.sh` and the backup script; not the stack dir):

```bash
git clone https://github.com/TheCommishDeuce/healthee.git /opt/healthee
```

**3. Create the stack in Dockge.** New Stack → name it `healthee` → paste
`infra/dockge/compose.yaml` → save. Dockge writes `/opt/stacks/healthee/compose.yaml`.

**4. The env file:**

```bash
cp /opt/healthee/infra/dockge/.env.example /opt/stacks/healthee/.env
$EDITOR /opt/stacks/healthee/.env
```

Must set: `HEALTHEE_BIND_ADDR` (step 1), `PUBLIC_HOST`, `POSTGRES_PASSWORD`, and the
Supabase values. `HEALTHEE_IMAGE` already points at the fork's GHCR package.

> ⛔ `HEALTHEE_BIND_ADDR` is the security boundary. `0.0.0.0` puts the API on the
> public internet with no TLS, no rate limit and a bearer token as the only check;
> `127.0.0.1` makes it unreachable from Traefik. Compose **refuses to start** if it
> is unset rather than guessing. `ufw deny 8765` does not substitute for it —
> Docker's iptables rules run ahead of ufw.

**5. First deploy** — from the repo, not Dockge's button, since every migration is
pending on an empty database:

```bash
/opt/healthee/infra/dockge/deploy.sh --dry-run    # read the plan first
/opt/healthee/infra/dockge/deploy.sh
```

It reports where the port ended up bound. Confirm it says *"private interface only"*.

**6. Prove the app is up, locally:**

```bash
curl -fsS http://<private-ip>:8765/healthz
```

### On the TRAEFIK host

**7. Confirm it can reach the other machine** — do this before anything else, it is
the thing most likely to be wrong:

```bash
curl -fsS http://<healthee-private-ip>:8765/healthz
```

If that fails, nothing downstream will work: check the private network, the bind
address, and any firewall between them. Do not proceed until it answers.

**8. Enable the file provider** in Traefik's static config, if it is not already:

```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

**9. Install the router config:**

```bash
PUBLIC_HOST=api.example.com HEALTHEE_BIND_ADDR=10.0.0.5 \
  /path/to/healthee/infra/traefik/render-dynamic.sh --install
```

Or render it on the Healthee box, where `.env` already holds both values, and pipe
it across:

```bash
/opt/healthee/infra/traefik/render-dynamic.sh | \
  ssh traefik-host 'sudo tee /etc/traefik/dynamic/healthee.yml >/dev/null'
```

With `watch: true` Traefik reloads on save.

**10. Point DNS for `PUBLIC_HOST` at the TRAEFIK host** — not at the Healthee box.
ACME validates by being reached, so a record on the wrong machine fails issuance and
leaves a self-signed cert, which looks like a TLS error rather than a routing bug.

### Then, from anywhere

```bash
curl -fsS https://api.example.com/healthz
```

**11. Finally, from a machine OUTSIDE the private network**, confirm the app is not
directly exposed. This must **fail**:

```bash
curl --max-time 5 http://<healthee-box-public-ip>:8765/healthz
```

Then work through `infra/traefik/CHECKLIST.md` — in particular §1 (rate-limiter IP
trust), §2 (tile paths in the access log) and §7 (the hop between the machines is
unencrypted).

---

## Sign-in — the self-hosted GoTrue

This deployment runs its **own** identity provider (the `auth` service) instead of
hosted Supabase. The API is a resource server: it only ever *verifies* what GoTrue
signs, never mints a token (`core/supabase_auth.py`).

Worth knowing before you start:

- **Supabase is not on the data path either way.** `/ingest/*` — the BLE firehose —
  uses a **device token your own server mints**: no expiry, only its SHA-256 stored,
  revocable. Only `/api/*` needs a live GoTrue JWT.
- **HS256 only.** `_jwks_url()` hardcodes `https://<ref>.supabase.co/…`, so the
  asymmetric path cannot reach a self-hosted instance. GoTrue and the API therefore
  **share one secret**, interpolated from a single `.env` key so they cannot drift.
- **`SUPABASE_SERVICE_ROLE_KEY` is read by nothing.** Declared in `core/config.py`,
  referenced by no code path in `apps/server/src` — verified by grep. Leave it blank.

### 1. Create the `gotrue` database role

GoTrue owns the **`auth` schema in the same database as your health data**. That is
deliberate: `pg_dump` then covers both. A separate database would give you a restore
with every measurement and no way to log in, because each `app_user` row keys off a
uuid GoTrue owns.

```bash
cd /opt/stacks/healthee
GOTRUE_PW=$(openssl rand -base64 48 | tr -d '/+=' | head -c 32); echo "$GOTRUE_PW"

docker compose exec -T db psql -U healthee -d healthee -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE gotrue LOGIN PASSWORD '$GOTRUE_PW';
GRANT CONNECT ON DATABASE healthee TO gotrue;
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION gotrue;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- ⛔ The four role NAMES Supabase's own migrations grant to. Without them GoTrue
-- dies on its first start with:
--     running db migrations: ... ERROR: role "postgres" does not exist (SQLSTATE 42704)
-- because this database was initialised as POSTGRES_USER=healthee, so there is no
-- `postgres` role for `20240612123726_enable_rls_update_grants` to GRANT to.
-- NOLOGIN on purpose: the migration only needs the names to EXIST so it can grant
-- to them. None of them gets a password or any way to connect.
CREATE ROLE postgres NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
SQL
```

> Already hit the error? The failed migration is a `DO $$ … $$` block, so it rolled
> back whole. Create the roles, then `docker compose up -d auth` — GoTrue resumes
> from `auth.schema_migrations` and its statements are idempotent.

The extension is created **as the admin** because GoTrue's migrations may need
`uuid_generate_v4()` and the `gotrue` role is deliberately not a superuser.

### 2. Secrets

```bash
# the shared signing secret — GoTrue signs with it, the API verifies with it
openssl rand -base64 48 | tr -d '/+=' | head -c 64
```

Put that in `SUPABASE_JWT_SECRET` and the password from step 1 in
`GOTRUE_DB_PASSWORD`, then mint the anon key:

```bash
/opt/healthee/infra/dockge/mint-anon-key.sh     # reads SUPABASE_JWT_SECRET from .env
```

> The anon key is public by construction — it ships in the app and authorises
> nothing alone. But it must be **non-empty**: the app reads an empty key as "this
> server has no sign-in configured" and never shows the form.

### 3. The rest of `.env`

```ini
SUPABASE_URL=https://<your PUBLIC_HOST>    # same host as the API
SUPABASE_PROJECT_REF=                      # ⚠ MUST stay blank
SUPABASE_ANON_KEY=<from step 2>
SUPABASE_JWT_SECRET=<from step 2>
SIGNUP_ALLOWLIST=you@example.com
GOTRUE_DISABLE_SIGNUP=false                # ⚠ flip to true after step 5
```

⚠ `SUPABASE_PROJECT_REF` blank is required, and it is a real trade: it makes the API
**skip the `iss` check** (`_expected_issuer` returns `None`). A ref would make the
API demand a `supabase.co` issuer and a JWKS url that does not exist here, so every
token would be refused.

### 4. Deploy and re-render Traefik

```bash
/opt/healthee/infra/dockge/deploy.sh
# on the Traefik host — the auth route is NEW, so this is not optional:
infra/traefik/render-dynamic.sh --install
```

The app asks for `https://<host>/auth/v1/…`; GoTrue serves those at its root, so
Traefik strips the prefix. Check it end to end:

```bash
curl -fsS https://<your-host>/auth/v1/health      # {"name":"GoTrue",...}
```

### 5. Create your account, then close the door

Sign in from the app (it will register you, autoconfirmed — there is no SMTP on this
box). Then:

```ini
GOTRUE_DISABLE_SIGNUP=true
```

and redeploy. Signup is gated twice on purpose — GoTrue's own flag and the API's
`SIGNUP_ALLOWLIST` — because creating an account is the one action a stranger could
take that you cannot undo from the app.

Finally, run the claim procedure (`DEPLOY.md` §B4) so your new uuid takes ownership
of the existing sentinel rows instead of starting an empty second tenant.

---

## Where the image comes from

Nothing is built by Dockge. The stack runs whatever `HEALTHEE_IMAGE` +
`HEALTHEE_IMAGE_TAG` name, and there are three sane ways to have one.

`HEALTHEE_IMAGE` has **no default** — compose refuses to start without it. The only
namespace it could sensibly default to is the upstream project's, and quietly running
an image you did not build, from a repo you do not control, is not a fallback worth
having.

### A. You forked the repo — recommended, and what this deployment uses

CI derives the namespace from **whichever repository ran it**
(`github.repository_owner`) and lowercases it, so a fork publishes to the fork's
owner with no edit to the workflow:

```ini
HEALTHEE_IMAGE=ghcr.io/<your-github-user>/healthee-api   # lowercase!
HEALTHEE_IMAGE_TAG=main
HEALTHEE_BUILD_LOCALLY=false
```

> ⚠ **A fork does not run workflows until you say so.** GitHub registers zero
> workflows on a new fork; the Actions tab shows a banner and you must click
> *"I understand my workflows, go ahead and enable them"* once. Until you do, no
> image is ever published and the only symptom is a `manifest unknown` on the VPS
> hours later. Check `gh api repos/<you>/healthee/actions/workflows` returns a
> non-zero `total_count` before your first deploy.

Push to your fork's `main` and let CI finish. The package inherits the **fork's**
visibility: a public fork publishes a publicly pullable image and the VPS needs no
credentials at all. Verified for this deployment — an anonymous manifest fetch of
`ghcr.io/thecommishdeuce/healthee-api:main` returns 200.

If your fork is **private**, so is the package, and the first pull on the box fails
with `denied` / `manifest unknown` — which says nothing about permissions. Log the
box in once, with a classic PAT scoped `read:packages`:

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <you> --password-stdin
```

Dockge shares the Docker daemon, so its update button uses this login too.

Check either case from anywhere, without Docker:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:<you>/healthee-api:pull&service=ghcr.io" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('token',''))")
curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/<you>/healthee-api/tags/list
```

### B. Your own registry

Any registry you can push to — Docker Hub, a private Harbor, a VPS registry:

```ini
HEALTHEE_IMAGE=registry.example.com/healthee-api
```

Build from the **repo root** (the Dockerfile copies `apps/server/*` and
`packages/knowledge`):

```bash
docker build -f infra/docker/Dockerfile.server -t registry.example.com/healthee-api:main .
docker push registry.example.com/healthee-api:main
```

### C. Build on the VPS — no registry at all

```ini
HEALTHEE_IMAGE=healthee-api
HEALTHEE_IMAGE_TAG=local
HEALTHEE_BUILD_LOCALLY=true
```

`deploy.sh` then builds from the checkout instead of pulling.

> ⚠ **This costs you the update button.** Dockge only ever *pulls*, so it can never
> obtain a new image here — every update, schema change or not, has to go through
> `deploy.sh`. It also puts a build toolchain and build load on the box. Worth it if
> you have nowhere to publish; otherwise prefer A.

---

## Updating: which path?

**Default to Dockge's update button.** It is `docker compose pull` + `up -d`, and the
`preflight` service makes that safe: it runs `migrate --check` on the newly pulled
image and `api`/`scheduler` are gated on it exiting 0.

- **Code-only release** → preflight passes → done, one click.
- **Schema change, or a release that added a required env var** → preflight **fails**
  and the update is refused. Its log names the pending migrations.

When it refuses, run the script — from Dockge's own terminal tab for the stack, so
you never leave the UI:

```bash
/opt/healthee/infra/dockge/deploy.sh
```

Only that path takes a backup and stops the app before the schema moves. Our
migrations are not backwards-compatible (0004 folds `user_id` into the natural keys;
0007 drops a DEFAULT), so this is a **deliberate, planned outage of about a minute**,
not an avoidable one.

> ⛔ Do not "fix" a failing preflight by removing it from `depends_on`. The gate is
> the only thing standing between the button and a new image writing health data
> against a schema it does not match.

---

## ⚠ Verify the refusal on first deploy — do not take this on trust

Everything above rests on one behaviour: **when `preflight` exits non-zero, compose
must abort without having removed the running `api`.** That was reasoned about, not
measured — there was no Docker available where this was written, and compose's exact
recreate ordering is a detail worth knowing rather than assuming. **Ten minutes, once,
while nobody depends on the box.**

```bash
cd /opt/stacks/healthee

# 1. Note the running container's id.
docker compose ps -q api

# 2. Force a refusal without a real schema change: point the preflight at a
#    migration ledger that cannot satisfy it.
docker compose run --rm --no-deps \
  -e POSTGRES_DB=definitely_not_a_database api python -m healthee.db.migrate --check
#    → must exit non-zero.

# 3. Now the real question — does a failing gate take the site down?
docker compose up -d
docker compose ps -q api        # same id as step 1? and still serving?
```

**If the id is unchanged and the api still answers** — the gate is
non-disruptive. A refused update costs nothing; note that here and move on.

**If the api was stopped or replaced** — the gate still works (it prevents the bad
image from *serving*), but a refusal now costs the same ~minute of downtime as the
planned migration outage. Nothing is unsafe; you just want to press update at a time
you would be willing to deploy. Record whichever you observe, and correct this
section.

---

## Day-2

**Logs.** Dockge shows each container. When the api will not start, read
`preflight` first — it is the thing that gated it, and it says why in one line.

**Rollback.** Images are tagged twice: `main` moves, `sha-<short>` does not.

```ini
HEALTHEE_IMAGE_TAG=sha-1a2b3c4      # in /opt/stacks/healthee/.env
```

Then press update. ⚠ This rolls back **code only** — it does not un-apply a
migration, and old code cannot serve a migrated schema. A rollback across a schema
change is a restore, not a tag change: `infra/backup/RESTORE.md`.

**Backups.** Still the systemd timer (`infra/backup/`), and `deploy.sh` takes one
before every migration. The unit file hardcodes a path — point `ExecStart` at
`/opt/healthee/infra/backup/pg_dump_backup.sh` and set `BACKUP_DIR` in the stack's
`.env`. Test the restore drill before you need it.

**Secrets** are in `/opt/stacks/healthee/.env`, which Dockge can edit in the browser.
Whoever can reach Dockge can read your Supabase service-role key and your OpenRouter
key. Put Dockge behind auth and do not expose it publicly.

---

## Gotchas

- **`compose.yaml` is not in the image.** Editing it in the repo does nothing to the
  box until `deploy.sh` syncs it (it prints the diff and keeps a `.bak` first). A
  release that adds a service needs the script, not the button.
- **Editing `.env` in Dockge's UI needs a redeploy** to take effect — a running
  container does not re-read it.
- **`POSTGRES_HOST`, `API_HOST` and `API_PORT` are pinned in `compose.yaml`** and
  override the `.env`. They are topology, not choice; changing them in the UI does
  nothing, deliberately.
- **`curl localhost:8765` on the Healthee box fails, and that is correct.** The port
  is published on the private IP only, not on loopback. Use
  `curl http://<private-ip>:8765/healthz`, or from inside the container:
  `docker compose exec api python -c "import urllib.request;
  print(urllib.request.urlopen('http://localhost:8765/healthz').read())"`
- **Only `api` publishes a port.** `db`, `scheduler` and `preflight` have no HTTP
  surface and stay on the internal compose network. A test enforces this — on a box
  another machine can reach, publishing Postgres would be a real exposure.
- **The two machines each hold half the routing and nothing reconciles them.**
  Change `HEALTHEE_BIND_ADDR` or `PUBLIC_HOST` and you must re-run
  `infra/traefik/render-dynamic.sh` on the Traefik host. A stale backend address is
  a 502 with a perfectly healthy stack behind it.
- **A 502 is almost always the private network, not the app.** First command, on the
  Traefik host: `curl http://<healthee-private-ip>:8765/healthz`. That one result
  splits the problem in half.
