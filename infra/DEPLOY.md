# Deploy runbook — Healthee

For the human at 2am. Everything here is run **on the VPS** (`ssh contabo`), from
the repo root, and all of it assumes:

```sh
cd <the repo checkout>    # find it: `ls -d ~/healthee*` — confirm `infra/deploy.sh` is there
COMPOSE="docker compose --env-file infra/.env -f infra/docker/docker-compose.prod.yml"
```

> The live checkout is **`~/healthee-new`** (confirmed 2026-07-17 from the running
> container's own compose label:
> `docker inspect healthee-api --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'`
> → `/home/afkcodes/healthee-new/infra/docker`). `~/healthee` **also exists** but is
> the legacy checkout — both dirs are real, which is why `ls` alone can't tell them
> apart; ask the running container. `deploy.sh` itself doesn't care: it locates the
> repo from its own path.

Related: `infra/backup/RESTORE.md` (restore drill) · `infra/.env.example` (every
var, annotated) · `docs/MULTI_USER.md` §3.3a (the app role) / §4.4b (owner
onboarding) / §8 (the data migration).

> **If you are deploying Phase 6 for the first time, do NOT start at section A.**
> Read **section B** first. It is a credential change and a schema change, and
> the order matters.

---

## A. Routine deploy (the happy path)

```sh
git push                      # ON YOUR LAPTOP, first. The VPS deploys from origin.
infra/deploy.sh --dry-run     # read the plan
infra/deploy.sh               # do it
```

`deploy.sh` is the only supported way to deploy. It:

1. **Preflights** and reads `infra/.env` (`DEPLOY_BRANCH`, default `main`).
2. **Refuses** if the local branch has commits not on origin — the VPS deploys
   via `git reset --hard origin/<branch>`, so unpushed work is silently lost.
3. `git reset --hard origin/<branch>`.
4. **Builds** the api image (the scheduler shares it).
5. **Backs up** the DB via `backup/pg_dump_backup.sh`. A failed backup **aborts
   the deploy**.
6. **Stops** `api` + `scheduler`. ⏱ **The outage starts here.**
7. **Migrates**: `$COMPOSE run --rm api python -m healthee.db.migrate`.
8. **Provisions** the app role — every deploy, idempotently (see B). Skipped when
   `POSTGRES_APP_*` are unset.
9. **Recreates** `api` **and** `scheduler`.
10. Polls `/healthz`, then reports **which DB role the app connected as**.

### Why there is an outage

The migrations are **not backwards-compatible**. `0004` folds `user_id` into the
natural keys (old code's `ON CONFLICT (day, metric)` then matches no constraint)
and `0007` drops the `user_id` DEFAULT (old owner-less INSERTs become
`NotNullViolation`). Old code **cannot** serve the new schema, so there is no
zero-downtime path — leaving the containers up during the migration would just
mean erroring mid-write. The api is down from step 6 to step 9, on purpose. For a
routine deploy with no pending migrations that is a container restart (seconds).

### What "healthy" looks like

```
▶ Health check
  ✓ healthy after 3 attempt(s): http://127.0.0.1:8765/healthz

▶ Verifying the DB identity the app pool connected as
  ✓ RLS is real — the pool is on the least-privilege role (NOSUPERUSER NOBYPASSRLS).

▶ Deploy OK
```

Anything other than `Deploy OK` (exit 0) means it did not finish. Two non-fatal
warnings you may see, both explained below: the app role being **skipped**, and
the pool being on a role that **BYPASSES Row-Level Security**.

### If it fails

- **Backup failed** → nothing was stopped or changed. Fix the backup first
  (`RESTORE.md`, `BACKUP_DIR` free space, `db` running); do not skip it.
- **Migration failed** → `api` + `scheduler` are **stopped and must stay
  stopped**. The schema may be half-moved, and old code cannot serve the new one
  regardless. Read the error, fix forward, re-run `deploy.sh` (the runner records
  each file in `schema_migrations`, so applied migrations are skipped on the
  re-run and each file is applied in its own transaction — a failed file rolled
  back cleanly).
- **Health check failed** → the script dumps the last api + scheduler logs and
  exits 1. Start there.

### The embedding index artifact (Step 2a hybrid retrieval)

Step 8b (`$COMPOSE exec -T api python -m healthee.insights.embedding_index --check`)
is a HASH COMPARISON ONLY — no model load, no network, no embedding pass. The passage
matrix itself is a **committed artifact** (`packages/knowledge/embeddings/`, built on a
dev machine and checked into git like the manifest): this box's headroom (4 CPUs, 5 GB
RAM, under 1 GB free, no swap) cannot safely run the embedding pass itself, so `deploy.sh`
never builds it here. `--check` just confirms the deployed corpus still matches the
committed key. **Warn-only by design**: `insights/retrieval.py` falls back to
explicit+lexical ranking (today's ranking, minus the similarity term) if the artifact is
ever missing or stale, so a failed check here never blocks a deploy — you'll see a `⚠`
naming the fix (regenerate on a dev machine with `--build`, commit the result) and the
api keeps serving. The ONNX model FILE itself still downloads to the `healthee-geocache`
volume on first use (query embedding needs a live model regardless of the artifact) —
that part is unchanged and small enough (69 MB, one-time) to not need special handling.

The coach's evidence reranker (Step 2b, `insights/evidence.py`) follows the identical
shape for its own ~88 MB model: same `EMBEDDING_CACHE_DIR` setting, same `healthee-geocache`
volume, downloaded once on first coach question. A load failure degrades to the fused
hybrid order (logged once) rather than blocking a deploy, same as above.

### Rollback

**There are no down-migrations.** Once `0002`→`0008` have applied, rolling the
*code* back does not roll the *schema* back, and the old code cannot run against
the new schema. So a post-migration rollback is a **restore**, not a checkout:

1. `$COMPOSE stop api scheduler`
2. Restore the pre-deploy dump — **`infra/backup/RESTORE.md` § "Real restore"**.
   The dump `deploy.sh` took in step 5 is the newest file in `$BACKUP_DIR`.
3. Deploy the previous known-good commit: point `DEPLOY_BRANCH` at it (or reset
   the branch on origin — the guard deploys origin's version) and re-run
   `deploy.sh`.

Before any migration has applied, a rollback is just step 3.

> ⚠ **Unverified — ask before relying on it.** There is a known
> rename-based rollback to the *pre-cutover legacy stack* (stop the new
> containers, `docker rename healthee-db-legacy healthee-db` + api/scheduler,
> start). **Nothing in this repo describes it**, so the exact container names and
> steps are not verifiable here and are deliberately not written out. If you need
> it, check the live box (`docker ps -a | grep legacy`) and confirm before acting.
> That path also predates `0002`→`0008` — the legacy stack has its own DB volume,
> so any data written after the cutover would not be in it.

---

## B. The ONE-TIME Phase 6 cutover

Prod's DB is at **`0001`**. `main` needs **`0002`→`0008`**. This is both a schema
change and a **credential change**. Read all of B before running anything.

### B1. Env that must be in `infra/.env` BEFORE you deploy

Compose now passes these through; it previously did not, so they may be absent on
prod even if they look familiar. Annotated in full in `infra/.env.example`.

The table below is checked against `core/config.py::Settings` by
`tests/test_env_templates.py` only as far as the *templates* go — the wording here
is maintained by hand, so it is re-read against `Settings` whenever a var is added.

| Var | If missing / blank |
|---|---|
| `SUPABASE_JWT_SECRET` | Auth **fails closed** — every Supabase JWT is refused. The server silently degrades to **legacy-token-only**: it stays up and the old app keeps working, so this failure is invisible unless you test a real login. |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side Supabase calls unavailable. |
| `SUPABASE_PROJECT_REF` | The `iss` check is **skipped** (intended for dev/self-signed tokens — on prod, set it). |
| `SUPABASE_JWT_AUD` | Defaults to `authenticated` (the Supabase default). |
| `SIGNUPS_OPEN` | Defaults to `false` — the correct posture. **See B5 before changing it.** |
| `SIGNUP_ALLOWLIST` | Empty ⇒ nobody new can sign up. This is also what makes owner onboarding possible (B4) — the claim cannot be run without it. |
| `DEFAULT_MODEL` / `COACH_MODEL` | **Required whenever `OPENROUTER_API_KEY` is set.** A blank id is forwarded to OpenRouter verbatim and comes back **400** — on every LLM surface, *including the nightly chain* in the scheduler. **The api and scheduler now REFUSE TO START** in that state (`core/config._require_model_ids_when_ai_key_is_set`), so `deploy.sh`'s `/healthz` wait fails and you see it here rather than in Telegram a week later. Blank key + blank ids is still fine: that is "no AI layer", a valid configuration. |
| `LLM_TIMEOUT_S` / `LLM_MAX_RETRIES` | Default to `60` / `1` (compose supplies those defaults). Unset in *code* the SDK would use 600 s × 3 attempts = a 30-minute hang, and the scheduler's tick loop is single-threaded, so one stuck call costs every later owner their chain. Raise the timeout only for a slow reasoning-tier `DEFAULT_MODEL`. |
| `LLM_LOW_BALANCE_USD` | Defaults to `20`. The balance below which the **scheduler** warns to Telegram (`jobs/llm_watch.py`). Warning only — nothing stops spending. Blank/0 leaves only the `exhausted` alert, which fires when every call is already 402ing. See **E** for why this exists. |
| `LOG_LEVEL` | Defaults to `INFO`. |
| `POSTGRES_APP_USER` / `POSTGRES_APP_PASSWORD` | The app falls back to the **admin** credentials, which bypass RLS. Loud startup WARNING. **Read B2 before setting these.** |

### B2. The credential ORDER (wrong order = the app cannot reach Postgres at all)

The app role must **exist** before the app is told to connect as it. `deploy.sh`
now provisions the role on every run, but it only does so when
`POSTGRES_APP_USER`/`POSTGRES_APP_PASSWORD` are set — the same vars the app pool
reads. So:

1. **Deploy once with the app vars blank and the fallback explicitly allowed.** The
   admin-cred fallback keeps the app alive; provisioning is skipped; you get the
   `BYPASSES Row-Level Security` warning. That is expected at this step — and the app
   now refuses to boot on that fallback unless you ask for it, so step 1 needs the
   opt-out in `infra/.env`:
   ```sh
   ALLOW_ADMIN_DB_FALLBACK=true
   ```
   ```sh
   infra/deploy.sh
   ```
2. **Set both, and remove the opt-out** in `infra/.env`:
   ```sh
   # openssl rand -base64 48 | tr -d '/+=' | head -c 32
   POSTGRES_APP_USER=healthee_app
   POSTGRES_APP_PASSWORD=<secret>
   # delete ALLOW_ADMIN_DB_FALLBACK, or set it to false
   ```
3. **Deploy again.** This run provisions the role (as the admin, password from
   the env) and then starts the app on it.
   ```sh
   infra/deploy.sh
   ```
4. **Confirm** the final step prints:
   `✓ RLS is real — the pool is on the least-privilege role`.

Setting the vars *before* the role exists means the app tries to authenticate as
a role Postgres has never heard of: total failure, not degradation.

**Why it re-provisions every deploy:** a role provisioned by *older* code lacks
`timescaledb.enable_skipscan=off`, and without that setting `/api/today` **500s
for every user** under RLS (a TimescaleDB 2.26.4 planner bug — see
`db/provision_app_role.py`). Re-provisioning keeps the role current and un-drifts
a role someone hand-altered. It is idempotent and quiet.

### B3. What `0002`→`0008` do to LIVE data

`deploy.sh` takes a backup immediately before this. The outage is the migration
window (§A "Why there is an outage"). One line each — full detail in
`MULTI_USER.md` §8:

| | |
|---|---|
| `0002` | Identity tables (`app_user`, `device_token`). Additive. |
| `0003` | Adds `user_id` to all 16 data tables and **backfills every existing row to the sentinel owner** (`00000000-…-0000`) + FK + index. That backfill is *correct*: all of it is the owner's data. Metadata-only, no table rewrite. |
| `0004` | Folds `user_id` into every natural key (PK/UNIQUE rebuild). **This is the breaking one** — old `ON CONFLICT` targets stop matching. |
| `0005` | Re-keys `profile` by owner (drops the `id INTEGER PK CHECK (id = 1)` single-row coupling). Drops a column. |
| `0006` | `device_token`'s FK → `ON UPDATE CASCADE`, so the claim's re-key doesn't error for an owner with a paired device. |
| `0007` | Drops the transitional `user_id` DEFAULT (`NOT NULL` stays). A writer that forgets the owner now raises instead of silently misattributing data. |
| `0008` | Row-Level Security + policies on every tenant table. |

After this, prod's data all belongs to the **sentinel** owner. It works — the
legacy token resolves to the sentinel — but it is not yet *your account*. That is
B4.

### B4. Owner onboarding — the claim (`MULTI_USER.md` §4.4b, §8)

**The deadlock this resolves:** `claim_sentinel` refuses a target who has never
signed in (it needs their `app_user` row, and re-keying a life of health data
onto a typo'd UUID is not undoable). But with signups closed they can never *get*
a row. The allowlist is the way out.

1. Put the owner's email in `infra/.env`:
   ```sh
   SIGNUP_ALLOWLIST=owner@example.com
   ```
2. Restart so the API sees it:
   ```sh
   infra/deploy.sh
   ```
3. **They sign in once** via the app/web with Supabase. The gate lets them
   through and JIT-provisions their `app_user` row under their real UUID. Get
   that UUID (Supabase dashboard, or the API's provisioning log line).
4. **Dry run first** — it prints the target's **email**, so you confirm you are
   handing the data to the right *human*, not just to a UUID that parsed:
   ```sh
   $COMPOSE run --rm api python -m healthee.db.claim_sentinel <uuid>
   ```
   Read the plan: source id, target id, target email, per-table row counts.
5. If and only if that email is right:
   ```sh
   $COMPOSE run --rm api python -m healthee.db.claim_sentinel <uuid> --apply
   ```
   One transaction; it post-checks that **nothing** anywhere still belongs to the
   sentinel, and rolls the whole thing back if anything does.
6. Optionally clear `SIGNUP_ALLOWLIST` and redeploy. They keep working — an
   owner who already has a row is never gated.

It refuses rather than guesses: target == sentinel · target never signed in ·
target already owns data (a merge is a judgement call, not this tool's to make).
Nothing to move ⇒ it says so and exits 0, so a re-run after success is a no-op.

### B5. `SIGNUPS_OPEN=true` — the gate is now open

**Both preconditions are met.** The app ships Supabase login, and B7 is done: the
legacy shared token was cleared in production on 2026-09-10 and the branch that gave
it meaning was deleted from `core/request_auth.py`. There is no longer a credential
that authenticates as a tenant without being issued to a person, so the combination
this section used to refuse is not configurable. `core/config.py`'s validator was
removed with the setting — a pair that cannot exist needs no guard.

⚠ **What still gates it is COST, not safety.** Every active owner gets a nightly LLM
chain, so opening signups opens your bill to strangers. Use `SIGNUP_ALLOWLIST` unless
you mean it. The paragraph below is kept as the record of why this was ever shut.

<details><summary>Why this was gated (historical)</summary>

A shared secret that
resolves to a real tenant must never coexist with open signups: anyone holding it
reads and writes that tenant's health data. That is exactly the hole
`MULTI_USER.md` §12.7 exists to close. Opening signups is gated on **removing the
legacy token branch**, not on the flag existing.

(Uncontrolled signup is also uncontrolled LLM spend — every active owner gets a
nightly chain. Since 6.6a the chain **skips the LLM steps for a non-premium owner**,
which is the structural half of that bound; the signup gate is still the other half.)

---

### B6. ⛔ ENTITLE THE OWNER BEFORE THE 6.6a GATE REACHES PROD

**This is the one step that breaks the live owner if you skip it.** Migration `0011`
adds the `subscription` table, and from that deploy on **every AI surface refuses an
owner who has no active row**: the coach, the four insight cards, `/api/notable`, the
challenges and programs system, `/api/today`'s `action` and `recommendations`, and the
nightly recs/warm/briefing. "Not premium" is the default and it is silent — the API
stays green, the tracker keeps working, and the AI layer simply stops.

Today's owner authenticates with the legacy shared token and resolves to the
**sentinel** (`00000000-0000-0000-0000-000000000000`) unless B4's claim has already
re-keyed them. They have no `subscription` row. So, in the same maintenance window:

```sh
cd ~/healthee-new/infra/docker

# 1. migrate (0011 creates the table; 0009/0010 may also still be pending)
docker compose -f docker-compose.prod.yml exec api python -m healthee.db.migrate

# 2. re-run the app-role provisioner. NOT optional: 0011 is a new table, so the
#    default privileges hand the app role full DML on it, and this is what REVOKEs
#    the writes back down to SELECT (entitlement must not be app-settable).
docker compose -f docker-compose.prod.yml exec api python -m healthee.db.provision_app_role

# 3. find the owner's UUID (the sentinel, or their real id if B4 already ran)
docker compose -f docker-compose.prod.yml exec db \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, email FROM app_user;"

# 4. DRY RUN — read the plan (before/after, the email, the end date)
docker compose -f docker-compose.prod.yml exec api \
  python -m healthee.db.grant_premium <owner-uuid> --months 120

# 5. apply
docker compose -f docker-compose.prod.yml exec api \
  python -m healthee.db.grant_premium <owner-uuid> --months 120 --apply --by owner \
  --note "product owner, pre-billing"
```

Verify in the running image, not the repo:

```sh
# `/api/*` takes a Supabase JWT and nothing else, so this needs one from a signed-in
# app — there is no shared token to paste any more. Copy the access token out of the
# phone's session, or check the DB directly, which needs no credential at all:
docker exec -i healthee-db psql -U healthee -d healthee -t -A -c \
  "SELECT count(*) FROM entitlement WHERE user_id = '<uuid>' AND premium;"   # → 1
```

**The alternative, for a self-hosted box only:** set `SELF_HOST_UNLOCKED=true` in
`infra/.env` (it is passed to BOTH the `api` and `scheduler` services). That entitles
every owner on the deployment, which is right when the operator pays their own
OpenRouter bill and wrong on the hosted service — both containers log a WARNING on
every boot when it is set, so an accidental one is visible in `docker compose logs`.

Rollback of just this step: `grant_premium <uuid> --revoke --apply` (writes `canceled`;
the row and its history are kept).

---

### B7. Retiring the shared token — ✅ DONE 2026-09-10

The token was cleared in `infra/.env` and the branch reading it was deleted from
`core/request_auth.py`, so this section is history rather than a procedure. It is kept
because the ORDER is the reusable part: every step below was reversible until the last,
and that is what made a change to live auth safe to make.

Everything before this made per-owner identity *possible*. This was the step that
made it *exclusive*. Until it was done, `REALTIME_INGEST_TOKEN` was a
never-expiring string that authenticates as a whole tenant with no identity
attached, and handing it to a second person hands them the first person's health
record.

**Order matters, and every step is reversible until the last.**

1. **Ship the app build with an identity provider.** Two new dart-defines, both
   public by design — the anon key identifies the project and authorises nothing
   on its own:
   ```sh
   flutter build apk --release \
     --dart-define=HELIO_API="https://$PUBLIC_HOST" \
     --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=<the anon key, NOT the service_role key>
   ```
   ⛔ `SUPABASE_SERVICE_ROLE_KEY` bypasses every policy and belongs only on the
   server. It must never be given to a build.

   A build without these still works: it shows the pasted-token form and says so.
   That is the self-hoster with no Supabase project, and it is a supported state.

2. **Allowlist the owner and sign in**, exactly as B4 describes. The app will
   mint this phone a device token of its own on that sign-in.

3. **Run the claim** (B4 steps 4–5) so the owner's history moves from the
   sentinel to their real UUID. Their phone keeps working throughout: it is
   holding a device token, and `device_token`'s FK is `ON UPDATE CASCADE`, so the
   re-key takes the token with it.

4. **Verify the phone is off the shared token before removing it.** The one check
   that matters, and it is a `SELECT`:
   ```sh
   ssh contabo 'docker exec -i healthee-db psql -U healthee -d healthee -t -A -c \
     "SELECT count(*) FROM device_token WHERE revoked_at IS NULL;"'
   ```
   A count of at least one means a phone has its own credential. Zero means the
   only thing reaching `/ingest/*` is still the shared token, and removing it now
   stops ingestion.

5. **Remove `REALTIME_INGEST_TOKEN` from `infra/.env`** and redeploy. Blank failed
   closed — the comparison authorised *nobody* rather than matching everything — so a
   pasted token stopped working immediately while a device token and a JWT went on
   working. **This is the last reversible step**: putting the value back restored the
   old behaviour until step 6.

6. **Delete the branch itself**, which is what makes the removal permanent rather
   than a setting somebody can put back. Done 2026-09-10.

7. **Now** `SIGNUPS_OPEN=true` (or an allowlist) is safe on the auth side. It is still
   a spending decision — see B5.

7. **Delete the transitional code.** It is dead once the secret is gone, and dead
   auth scaffolding is the kind that comes back:
   * `core/request_auth.py` — the `_legacy_shared_token` / `_sentinel_user` branch
     of both dependencies;
   * `data/api/server_session.dart` — `signInWithToken`;
   * `features/signin/widgets/token_signin_form.dart` — the whole file;
   * `StoredCredentialKind.shared` and the code that reads it.

**Rollback.** Steps 1–4 change nothing on the server. Step 5 is one line in
`.env` and a redeploy; putting it back restores the old behaviour exactly, and
nothing about a device token or a JWT is affected either way. Step 3 is the one
that is not casually reversible — it is a data re-key — and it is the step
`claim_sentinel` makes you dry-run first, printing the target's email so you
confirm the human and not just a UUID that parsed.

---

## C. Verification checklist (after any deploy)

- [ ] **`deploy.sh` exited 0** and printed `▶ Deploy OK`.
- [ ] **`/healthz`** →
      `curl -fsS http://127.0.0.1:8765/healthz` (it does a real `SELECT 1`, so a
      200 means the DB is reachable too).
- [ ] **Public** → `curl -fsS "https://$PUBLIC_HOST/healthz"` (proves nginx →
      127.0.0.1:8765 too). `PUBLIC_HOST` comes from `infra/.env`, so this line is
      copy-pasteable on any deployment without editing it.
- [ ] **The DB role line** → the script's last step. `connected as least-privilege
      role` = RLS is real. `BYPASSES Row-Level Security` = the fallback is active;
      not fatal, but RLS is isolating nothing — go to B2.
      By hand: `$COMPOSE logs api | grep -i 'db pool'`.
- [ ] **A real authenticated read** →
      `curl -H "Authorization: Bearer <token>" "https://$PUBLIC_HOST/api/today"`
      → **200**. This is the check that catches the RLS/skipscan failure and any
      tenant-scoping break; `/healthz` cannot. Do it after every Phase 6 deploy.
- [ ] **Migrations are where you think** →
      `$COMPOSE run --rm api python -m healthee.db.migrate` again; it should say
      `no pending migrations`. (It is a no-op when nothing is pending.)
- [ ] **The scheduler is actually up and on the new code** →
      `$COMPOSE ps scheduler` (Up, not Restarting) and
      `$COMPOSE logs --tail 30 scheduler`. A crash-looping scheduler leaves
      `/healthz` green and the nightly chain dead.
- [ ] **Failures surface in Telegram**, not in the terminal: every supervised
      chain step reports there on failure (`TELEGRAM_BOT_TOKEN` /
      `TELEGRAM_CHAT_ID`; blank ⇒ silent no-op — so a blank token means job
      failures go **nowhere**). The nightly chain runs on IST timers, so the real
      proof of a scheduler deploy arrives the next morning.
- [ ] **`/readyz`** → `curl -sS http://127.0.0.1:8765/readyz | python3 -m json.tool`.
      This is the probe that knows about the **AI layer**; `/healthz` deliberately
      does not (see **E**). Read the `llm` block:
      `transport` is `unknown` until this process has made an LLM call — that is
      honest, not a fault, and it turns `ok` after the first one;
      `balance` must be `ok`, and `balance_checked: false` means we could **not
      measure** it (`balance_error` says why — a 401 there means the key is dead).
      A `503` here with `db: ok` is an AI-layer outage, not a server outage: do
      **not** restart anything, go top up or rotate the key.
- [ ] **The derived layer is current, not just the raw one** →
      `$COMPOSE exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT metric,
      max(day) FROM derived_daily GROUP BY metric ORDER BY 2 DESC, 1;"` — the night
      metrics (`rhr_daily`, `hrv_sleep_avg`, `respiratory_rate_sleep`,
      `spo2_overnight`) must reach the same day as the day metrics. `data_health`
      cannot catch this: it measures raw sample **arrival**, not derivation, so it
      reads `ok` over an empty derived layer. Repair with **F**.
- [ ] **After a science change: the derived layer holds nothing the new code disowns** →
      the `rederive` run's `STALE` line (**F1**). A narrowing change (new required input,
      tightened range, withdrawn metric) leaves the OLD rows serving, dated today, and a
      plain re-derive does not remove them. This is the one the VO₂max fix needed and did
      not have.
- [ ] **The scheduler's LLM watch is armed** →
      `$COMPOSE logs --tail 50 scheduler`. Within one tick of start it probes the
      balance; if it is low or the key is dead you get a Telegram message, and if
      everything is fine you get **nothing** (edge-triggered by design).

---

## D. Rotating a secret

All app secrets live in **`infra/.env` on the box** (git-ignored — they are never
in the repo, and `git reset --hard` during a deploy does not touch `.env`). The
pattern is the same for all of them: **edit `infra/.env`, then restart the process
that reads it.** A code deploy is *not* required — the value is read at process
start, so a restart is enough. What differs per secret is (1) how you mint the new
value and (2) which process reads it.

Editing `.env` alone changes nothing on a running container — it is read once at
start. Always restart afterward (below), or the old value stays live.

### D1. Telegram bot token (`TELEGRAM_BOT_TOKEN`)

Read by the **scheduler** (it sends the nightly chain + failure alerts) — not the
api. So only the scheduler needs the restart.

1. **Mint it in BotFather** (Telegram): message `@BotFather` → `/token` (reissue for
   the existing bot) or `/newbot` (a brand-new bot — also gives a new username).
   `/revoke` kills the old token immediately; a reissue via `/token` also
   invalidates the previous one. **Rotation is the only thing that kills an
   already-leaked token** — changing the code that logs it does not.
2. **Edit `infra/.env`** on the box: set `TELEGRAM_BOT_TOKEN=<new>`. (If you made a
   *new* bot, send it a message first and update `TELEGRAM_CHAT_ID` too — a fresh
   bot cannot message you until you start a chat with it.)
3. **Restart the scheduler:**
   ```sh
   $COMPOSE up -d --force-recreate scheduler
   ```
4. **Confirm** — send a test line, and confirm the token is no longer printed in
   the log (the api pins httpx to WARNING since `f3776ac`, so the request URL — and
   the token in it — should not appear at all):
   ```sh
   $COMPOSE logs --tail 50 scheduler | grep -i telegram    # status lines, no token
   $COMPOSE logs scheduler | grep -c 'bot[0-9]'             # want 0 — no token in the URL
   ```

> The token sits in the Telegram **URL path** (`api.telegram.org/bot<TOKEN>/…`),
> which is why an HTTP client that logs request URLs leaks it. Treat any token that
> has ever appeared in a log or a terminal as burned — rotate it.

### D2. The other secrets — same shape, different mint + restart

| Secret | Where you get the new value | Restart |
|---|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai → Keys → create; delete the old key there to revoke it. | `api` **and** `scheduler` (both make LLM calls). |
| `POSTGRES_APP_PASSWORD` | You choose it (`openssl rand -base64 48 \| tr -d '/+=' \| head -c 32`). **Not** a self-service rotation: the role's password lives in Postgres too, so `deploy.sh` must re-run to re-provision the role with the new value — see **B2**. Editing `.env` alone will lock the app out (`.env` says X, Postgres still expects Y). | Run `infra/deploy.sh` (it re-provisions, then restarts). |
| `SUPABASE_JWT_SECRET` | Supabase dashboard → Project → **Settings → API → JWT Settings → JWT Secret**. Rotating it there invalidates every issued token, so every user re-logs in. | `api`. |
| `SUPABASE_SERVICE_ROLE_KEY` | Same page → **Project API keys → `service_role`** (Reveal / Roll). This key bypasses RLS — treat it like a root password. | `api`. |

### D3. What is `POSTGRES_APP_PASSWORD`? (the "app-role password")

Postgres has **two** roles for Healthee, on purpose:

- the **admin** role (superuser) — runs migrations, `TRUNCATE`, the role
  provisioning. It **bypasses Row-Level Security** (superusers always do).
- the **app** role (`POSTGRES_APP_USER` / `POSTGRES_APP_PASSWORD`, a *non*-superuser)
  — what the running API connects as to serve requests. Because it is **not** a
  superuser, RLS policies actually apply to it, so a query that forgets the tenant
  filter returns *nothing* instead of another user's rows.

`POSTGRES_APP_PASSWORD` is **a value you invent**, not one issued by a service — it
is the password for that second role. It has to match in two places (the Postgres
role and `infra/.env`), which is why changing it is a `deploy.sh` re-provision, not
a plain `.env` edit (**B2**). While it is unset, the app falls back to the admin
role and **RLS protects nothing** — fine with one owner, a hard blocker before a
second. See `docs/MULTI_USER.md` §3.3a.

### D4. What is `SUPABASE_PROJECT_REF`, and where do I get it?

Supabase is the managed **auth** provider (it issues the login JWT; our server only
*verifies* it — see `docs/MULTI_USER.md` §4). The **project ref** is your Supabase
project's short id — the `abcdefghijklmnop` in your project URL
`https://abcdefghijklmnop.supabase.co`. Find it in the Supabase dashboard: **Project
Settings → General → Reference ID** (or just read it out of the project URL / the
API URL on **Settings → API**).

It is **not a secret** (it is in every request URL to your project), so it is safe
to commit to `.env` and to name here. We use it to build the expected token issuer
`https://<ref>.supabase.co/auth/v1` and **reject** a JWT whose `iss` doesn't match —
so a valid-looking token minted by a *different* Supabase project is refused. Leave
it blank and that issuer check is **skipped** (intended only for dev / self-signed
tokens); on prod, set it. Restart `api` after adding it.

---

## E. The OpenRouter account — spend limits, keys, and how a dead AI layer surfaces

### E1. What happened (2026-08-01), because the fix only makes sense with it

The account hit its **$200 ceiling**. Every LLM call 402'd — the coach, every insight
card, the entire nightly chain — and `/healthz` returned `{"status":"ok","db":"ok"}` for
the duration. Nobody found out from monitoring; an unrelated eval run happened to die and
that is how it surfaced. It is the same shape as every earlier incident in this repo:
**`/healthz` was green in every broken state.**

Two causes, and both have a cheap fix below: there was **no spend limit**, and **eval/dev
work shared the production key** — the grounding-eval harness (`tests/grounding_eval/`,
~$3/arm) was draining the balance production runs on.

### E2. ⛔ Set a spend limit on the key (openrouter.ai → Keys)

Each OpenRouter key can carry a **credit limit**. Set one on the production key. It does
not prevent the outage — it *bounds* it, and more importantly it makes an eval key
incapable of emptying the account:

- **production key** — limit ≈ a month of expected spend (`docs/PRICING.md` §3.1 has the
  measured numbers). Set in `infra/.env` as `OPENROUTER_API_KEY`; rotation is **D2**.
- **eval/dev key** — a **separate key with a small limit** (a few dollars covers several
  harness arms). It lives in `apps/server/.env` on the dev machine as
  **`EVAL_OPENROUTER_API_KEY`** and **never** on the VPS. A drained eval key then costs
  you an eval run, not the live AI layer.

Same rule for any other key that runs experiments. The production key belongs to exactly
one thing: the production containers.

#### The code half is done (#124); the account half is still yours

`tests/grounding_eval/spend.py` reads `EVAL_OPENROUTER_API_KEY` and points the harness's
LLM client at it before the first paid call. It is **not** a gate — with the variable
unset an arm still runs on `OPENROUTER_API_KEY`, after printing a warning to stderr that
names #102, the ~$3 cost and what draining the balance takes down. Nothing broke the day
it landed; nobody spends production's credit on a 105-run arm without having been told.
`apps/server/.env.example` documents it, and `tests/test_env_templates.py` fails the build
if it ever appears in `infra/.env.example` — an eval key on the VPS is just the production
key again.

**Still OPEN, and only the owner can close it** (creating a key is an account action):

1. openrouter.ai → **Keys** → *Create key*, name it `healthee-eval`, set a **credit limit
   of ~$20** (an arm is ~$3, so that is several arms and a hard stop well below a month
   of production).
2. Put it in `apps/server/.env` on the dev machine only:
   `EVAL_OPENROUTER_API_KEY=sk-or-v1-…`
3. While in that screen, set the limit on the **production** key too (E2's first bullet) —
   it is the half that bounds an outage rather than preventing one.
4. Do **not** add it to `infra/.env` or `docker-compose.prod.yml`. The containers must
   never see it.

Until step 1 happens, every `run` prints the warning and spends production credit — which
is the intended failure mode (loud, not fatal), not a reason to skip the step. Current
balance is the thing to check first: `GET /readyz` reports it without a paid call.

### E3. What the server now does about it

Three pieces, none of which ever spends a token to check:

| Piece | Where | What it does |
|---|---|---|
| Transport record | `insights/transport_health.py` | Every real completion records ok/failed. **3 consecutive failures** = an outage; one 402 is a blip and is ignored. Stores the failure *kind* + HTTP status only — never the provider's message, which can contain the model id. |
| Balance probe | `insights/credits.py` | `GET /api/v1/credits` — **free, no tokens**. Also proves the key still works (a revoked key 401s here). TTL-cached. |
| The watcher | `jobs/llm_watch.py` (runs in the **scheduler**) | Pushes to the same Telegram channel as chain failures. **Edge-triggered**: once on the way in, once on recovery — never every tick. |

What you will actually receive, and how fast:

- **`⛔ LLM transport DOWN`** — within one scheduler tick (**≤ 5 min**) of the third
  consecutive failed call in that container. Names the kind (`credit` / `auth` /
  `rate_limit` / `timeout`) and whether waiting will help.
- **`⚠️ OpenRouter credits LOW`** — within the hour, at `LLM_LOW_BALANCE_USD`. This is
  the one that means you never see the others.
- **`⛔ OpenRouter credits EXHAUSTED`** / **`⚠️ balance check FAILED`** — same cadence.
  The second one matters: an *unmeasurable* balance is reported as **unknown**, never as
  fine. A monitoring feature that fails quiet is worse than none.
- **`✅ … recovered` / `healthy again`** — so a silent channel means "still broken", not
  "nobody is watching".

The pull-side view is **`GET /readyz`** (unauthenticated, no dollar figures — the amounts
go to Telegram). See the checklist in **C** for how to read it.

### E4. Why `/healthz` was deliberately left alone

Because a 503 on `/healthz` means *restart this container*, and that is all it may ever
mean: it is wired to the Docker healthcheck and to nginx. If it went 503 on a provider
outage, Docker would restart the API in a loop over something no restart can fix —
trading a dead AI layer for a flapping read API. `core/config.py` records the same
argument for the blank-model-id check. So the AI-layer signal lives on `/readyz`, which
nothing restarts on, and the **push** (Telegram) is what actually reaches a human.

---

## F. Rebuilding the derived layer (`rederive`)

The derived layer (`derived_daily`) is materialized, so it can be behind the raw
samples without anything looking wrong: pushes still return 200 and `data_health`
still reads **ok**, because that check measures raw sample *arrival*, not derivation.

```sh
$COMPOSE run --rm api python -m healthee.db.rederive                    # all owners, 42 d
$COMPOSE run --rm api python -m healthee.db.rederive --days 40
$COMPOSE run --rm api python -m healthee.db.rederive --user <uuid> --all
$COMPOSE run --rm api python -m healthee.db.rederive --all --rescore-tracks
```

It re-derives every stored **night** in the window and then every **day**, in that
order, through the same `derive.derive_batch` the ingest push uses — so the repair
and the live path cannot disagree about the order. It is idempotent (it recomputes
from raw samples it never touches), so there is no dry run and re-running is free.
One transaction per owner: a failure leaves that owner's derived layer as it was.

Recorded **GPS sessions** are part of the day pass since #111, so an ordinary run also
backfills any track that has never been scored. It will not recompute a track that
already carries an estimate — that freshness gate is what keeps a re-push from
re-reading every fix and re-running the DEM. `--rescore-tracks` forgets the estimates in
the window so the gate fires again; reach for it after a change to the VO₂max estimator
itself, and not otherwise.

**Run it after** a migration or a science change that alters what a derivation
computes, and after any incident where pushes were accepted but derivation was not
running. `--days 42` is the default because 42 is the longest trailing window any
derivation reads (the recovery baseline); sleep debt reads 14, SRI and VO₂max 7.

### ⛔ F1. The above was NOT enough after a science change that NARROWS (#118)

**Read this before believing a clean `rederive` run.** Until 2026-08-02 the instruction
in this section was *"run `rederive` after a science change"* — full stop — and for a
change that **stops a metric being written at all**, that instruction repaired nothing
while printing success.

`derived_daily` is written `INSERT … ON CONFLICT DO UPDATE`, and nothing in the product
deleted from it. So:

- a science fix that **changes a number** → the re-derive overwrites the row. Repaired.
- a science fix that **narrows what is written** — a new required input, a tightened
  validity range, a withdrawn metric → the new code correctly writes **nothing**, and
  every old row **survives, dated, and keeps being served**.

That is what happened with #108 (VO₂max now requires `profile.srpa`): **109
`vo2max_estimate` rows** stayed live, the newest dated *that same day* — so the read
layer's freshness rule ("is the newest row keyed to today?") could never call them stale
either. Production served 51.1 ml/kg/min from code that no longer existed, after the fix,
after the deploy, and after this runbook's repair step had been run.

**The tool now detects this on every run, unasked.** After it rebuilds a window it
reports, per metric, how many rows in that window it did **not** rewrite:

```
  00000000-…-0000 (Asia/Kolkata): 12 night(s), 42 day(s) 2026-06-22 → 2026-08-02, 0 GPS track(s) re-scored
  109 row(s) in this window are STALE — today's code would not write them
  (vo2max_estimate: 109). Remove with: --purge-stale vo2max_estimate --apply
```

A run that prints no `STALE` line found nothing to clean. **A run that prints one is
telling you the derived layer still holds numbers the current code disowns**, and no
amount of re-deriving will shift them.

### F2. Removing them — preview, then `--apply`

Unlike the recompute, this **deletes rows** and is therefore dry-run-first, exactly like
`claim_sentinel` and `grant_premium`. Reach for `--all`, not the default 42 days: the
rows a narrowing change orphaned are usually older than that.

```sh
# 1. PREVIEW — nothing is deleted. Read the per-metric counts.
$COMPOSE run --rm api python -m healthee.db.rederive \
  --user <uuid> --all --purge-stale vo2max_estimate

# 2. APPLY — only after the preview's numbers are what you expect.
$COMPOSE run --rm api python -m healthee.db.rederive \
  --user <uuid> --all --purge-stale vo2max_estimate --apply
```

It is bounded three ways and will not exceed any of them: the **owner**, the **day
window**, and the **metrics you name**. There is deliberately no "purge everything"
spelling — `--apply` without `--purge-stale` is refused rather than interpreted. The
counts it reports come from the DELETE itself, so `purged 109 stale row(s)` is 109 rows.

Two things to know before running it:

- **A metric it would have rewritten is never touched.** "Stale" means *this run did not
  write it*, and the run happens first — so a row the current code still produces has just
  been recomputed and is not a candidate. Removal only ever reaches rows today's code
  declines to produce.
- **`vo2max_submax` is refused** unless you also pass `--rescore-tracks`. A recorded GPS
  session is scored at most once, so an ordinary run never re-attempts it and its rows
  only *look* stale; purging them would delete every GPS-measured estimate you have. The
  tool refuses and names the flag.

**Rollback** is the pre-deploy dump (`infra/backup/RESTORE.md`) — a purged row cannot be
recomputed, because not being recomputable is the definition of what was purged. Take the
preview seriously; it is the whole safety story.

### ⛔ F3. `rederive` used to DESTROY the strap's step count (#121) — fixed forward only

Before #121 the strap's own since-midnight step counter (BLE 0x0016) was written straight
into `derived_daily.steps_total` after the derive pass and stored **nowhere else**. A
re-derive rebuilds that cell from the per-minute `steps_per_minute` sum — the stream the
code itself calls "possibly frozen/incomplete", and which demonstrably stalls — so every
run of the command in section F replaced the device's authoritative count with the worse
number, permanently. Measured on production 2026-08-02: of 143 `steps_total` rows, **142
carried the per-minute sum and exactly one carried `strap_0x16`.**

#121 gives the counter a raw table (`device_daily_total`, migration `0017`) that the day
pass reads, so `steps_total` and `distance_m_daily` are now derivations with a stated
precedence (device counter → per-minute sum) and a re-derive re-produces the same answer
however often it runs.

**The 142 days are gone and this deploy does not bring them back.** `device_daily_total`
starts empty; there is deliberately no backfill, because there is nothing to backfill
from — those numbers only ever existed in the cell that was overwritten, and two
pre-repair backups hold the same overwritten values. Days before this deploy keep the
per-minute sum, correctly labelled `flags.source = 'steps_per_minute'`. Which instrument
a day carries is readable directly:

```sh
$COMPOSE exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT flags->>'source' AS src, count(*), max(day) FROM derived_daily \
   WHERE metric = 'steps_total' GROUP BY 1 ORDER BY 2 DESC;"
```

### The symptom to recognise

Day metrics current (steps, calories, cardio load, MVPA) while `rhr_daily`,
`hrv_sleep_avg`, `respiratory_rate_sleep`, `spo2_overnight` and
`sleep_regularity_index` are **absent**, VO₂max is withheld on
`insufficient_rhr_days`, and `biological_age` is null. That is a night pass that has
not run. Check with:

```sh
$COMPOSE exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT metric, max(day) FROM derived_daily GROUP BY metric ORDER BY 2 DESC, 1;"
```

A metric whose `max(day)` is older than the others' is the one to chase.

The GPS variant of the same symptom is `gps_track` rows with a **null**
`vo2max_submax` while their windows clearly hold heart rate:

```sh
$COMPOSE exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT start_ts::date, vo2max_submax FROM gps_track ORDER BY start_ts DESC LIMIT 20;"
```

A null there is not automatically wrong — a flat walk genuinely cannot measure VO₂max
([[hr_reserve_vo2max]]) — but *every* row null is the shape #111 fixed.
