# Healthee on Dockge, behind Traefik

The stack: `db` (TimescaleDB) · `preflight` (one-shot gate) · `api` · `scheduler`.
Images come from GHCR, published by CI on every push to `main` — nothing is built
on the VPS.

| File | Goes where | Notes |
|---|---|---|
| `compose.yaml` | `/opt/stacks/healthee/compose.yaml` | synced from the repo by `deploy.sh` |
| `.env.example` | `/opt/stacks/healthee/.env` | fill in; never committed |
| `deploy.sh` | stays in the repo checkout | run for schema releases |

Traefik's own static config has two settings this repo cannot ship or test.
**Read `infra/traefik/CHECKLIST.md` before going live** — one of them is a privacy
property of the product, not a preference.

---

## First-time setup

**1. The proxy network** (skip if Traefik already has one):

```bash
docker network create proxy
```

**1b. Decide where the image comes from** — see the section below. The default in
`.env.example` points at the upstream project's namespace, which you can only pull
from if its owner has published it publicly. **If you are not the owner of the
repository, you almost certainly need to change `HEALTHEE_IMAGE`.**

**2. A repo checkout on the box** — `deploy.sh` and the backup script live here.
It is *not* the stack directory:

```bash
git clone https://github.com/afkcodes/healthee.git /opt/healthee
```

**3. Create the stack in Dockge.** New Stack → name it `healthee` → paste
`infra/dockge/compose.yaml` → save. Dockge writes `/opt/stacks/healthee/compose.yaml`.

**4. The env file:**

```bash
cp /opt/healthee/infra/dockge/.env.example /opt/stacks/healthee/.env
$EDITOR /opt/stacks/healthee/.env          # or edit it in Dockge's UI
```

At minimum set `PUBLIC_HOST`, `POSTGRES_PASSWORD`, and the Supabase values.
The `POSTGRES_APP_*` pair needs the two-deploy bootstrap in `infra/DEPLOY.md` §B2 —
read it; the wrong order leaves the app unable to reach Postgres at all.

**5. First deploy** — from the repo, not the button (the database is empty and every
migration is pending):

```bash
/opt/healthee/infra/dockge/deploy.sh --dry-run    # read the plan first
/opt/healthee/infra/dockge/deploy.sh
```

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

Push to your fork's `main`, let CI finish, then make the package pullable. A new
GHCR package is **private** by default and the first pull fails with `denied` /
`manifest unknown`, which says nothing about permissions:

- **Make it public** (simplest; the image holds no secrets — all config is env):
  `github.com/<you>?tab=packages` → `healthee-api` → Package settings → Change
  visibility.
- **Or keep it private** and log the box in once, with a classic PAT scoped
  `read:packages`:
  ```bash
  echo "$GHCR_PAT" | docker login ghcr.io -u <you> --password-stdin
  ```
  Dockge shares the Docker daemon, so its update button uses this login too.

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
- **No host port is published.** `curl localhost:8765` on the box will fail and that
  is correct — Traefik reaches the api on the proxy network. To probe it directly:
  `docker compose exec api python -c "import urllib.request;
  print(urllib.request.urlopen('http://localhost:8765/healthz').read())"`
- **`db` and `scheduler` are deliberately off the proxy network.** Neither has an
  HTTP surface. A test enforces this.
