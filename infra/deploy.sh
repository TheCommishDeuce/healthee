#!/usr/bin/env bash
# infra/deploy.sh — idempotent update-and-deploy for the Healthee VPS.
#
# Run ON the VPS, from anywhere inside the repo checkout — the script locates the
# repo from its OWN path, so it never depends on your cwd:
#   <repo>/infra/deploy.sh              # deploy
#   <repo>/infra/deploy.sh --dry-run    # print the plan, change nothing
#
# The checkout directory is deliberately NOT named here: this header used to say
# `cd ~/healthee`, while the cutover notes say `~/healthee-new`, and one of them is
# stale. A wrong path in a runbook is worse than no path — it sends a tired operator
# into the wrong (or an ancient) checkout. Confirm on the box before you deploy.
#
# What it does:
#   1. Preflight; verify the working tree's branch is pushed (local == origin/…).
#      The legacy repo's hard-learned rule: NEVER deploy code that isn't on
#      origin — the VPS deploys via `git reset --hard origin/...`, so anything
#      not pushed is silently lost.
#   2. git fetch && git reset --hard origin/<branch>
#   3. Build the api image.
#   4. BACKUP the database (backup/pg_dump_backup.sh). Abort on failure — the
#      migrations rebuild keys and drop a column on live data.
#   5. STOP api + scheduler.
#   6. MIGRATE: a one-off container on the NEW image, while db stays up.
#   7. PROVISION the least-privilege app role (only when POSTGRES_APP_* are set).
#   8. up -d --force-recreate api + scheduler.
#   9. Poll /healthz until healthy; clear pass/fail exit.
#  10. Report which DB role the app pool actually connected as.
#
# ⚠ THE STOP → MIGRATE → START WINDOW IS A DELIBERATE, PLANNED OUTAGE.
# Our migrations are NOT backwards-compatible: 0004 folds `user_id` into the
# natural keys (old code's `ON CONFLICT (day, metric)` then matches no
# constraint) and 0007 drops the `user_id` DEFAULT (old owner-less INSERTs
# become NotNullViolation). Old code CANNOT serve the new schema, so there is no
# zero-downtime path; leaving the containers up during the migration would only
# mean erroring mid-write instead of being honestly down for ~a minute.
#
# Migrations run BEFORE the new containers start so new code never serves the
# old schema either — the api is down across the whole transition, on purpose.
#
# Branch comes from DEPLOY_BRANCH in infra/.env (default: main).
# Full operator procedure — env, the one-time Phase 6 cutover, rollback:
# infra/DEPLOY.md.

set -euo pipefail

# ── Locate repo + compose file ──────────────────────────────────────────
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
compose_file="$script_dir/docker/docker-compose.prod.yml"
env_file="$script_dir/.env"
backup_script="$script_dir/backup/pg_dump_backup.sh"
cd "$repo_root"

COMPOSE="docker compose --env-file $env_file -f $compose_file"

# ── UI helpers ──────────────────────────────────────────────────────────
step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠ %s\033[0m\n' "$1" >&2; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
	cat <<'EOF'
Usage: infra/deploy.sh [--dry-run]

  --dry-run   Print every command this deploy would run, in order, with the
              resolved branch and services — and change nothing. This script
              cannot be rehearsed and it takes prod down; use this first.
  -h, --help  Show this help.
EOF
}

# ── Arguments ───────────────────────────────────────────────────────────
dry_run=0
for arg in "$@"; do
	case "$arg" in
	--dry-run) dry_run=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $arg (try --help)" ;;
	esac
done

# Run a command, or (in --dry-run) print exactly what would have run.
# Read-only inspection (git fetch/rev-parse, docker compose logs) is NOT routed
# through this — it is harmless and it is what resolves the plan we print.
run() {
	if [ "$dry_run" -eq 1 ]; then
		printf '  \033[2m$ %s\033[0m\n' "$*"
		return 0
	fi
	"$@"
}

# ── Preflight ───────────────────────────────────────────────────────────
step "Preflight"
[ -f "$compose_file" ] || die "compose file not found: $compose_file"
[ -f "$env_file" ] || die "env file not found: $env_file (copy infra/.env.example)"
[ -x "$backup_script" ] || die "backup script not found or not executable: $backup_script"
command -v docker >/dev/null 2>&1 || die "docker not found"

set -a
# shellcheck source=/dev/null
. "$env_file"
set +a
branch="${DEPLOY_BRANCH:-main}"
ok "deploy branch: $branch"
# Reported, never required. A deploy that refused to run without a public name
# would block the one case that needs it least — a box you are still bringing up,
# where nginx is not in front yet.
if [ -n "${PUBLIC_HOST:-}" ]; then
	ok "public host: $PUBLIC_HOST"
else
	warn "PUBLIC_HOST is not set in $env_file — the edge check at the end will be skipped.
    It is what renders the nginx vhost (infra/nginx/render-vhost.sh) and what keeps
    anybody's real domain out of the repository. See infra/.env.example."
fi
# Not `[ … ] && ok …` — that compound returns 1 when dry_run=0, which under
# `set -e` would exit the script here.
if [ "$dry_run" -eq 1 ]; then
	ok "DRY RUN — nothing below will be executed"
fi

# ── 1. Verify local == origin (the push-before-deploy guard) ────────────
step "Verifying $branch is pushed"
git fetch --quiet origin "$branch" || die "git fetch failed for origin/$branch"

local_sha="$(git rev-parse "$branch" 2>/dev/null || echo "")"
remote_sha="$(git rev-parse "origin/$branch")"

if [ -n "$local_sha" ] && [ "$local_sha" != "$remote_sha" ]; then
	# Local branch exists but differs — only abort if local is AHEAD (unpushed
	# commits would be lost by the reset). Behind/diverged-from-remote is fine
	# since we deploy origin's version anyway.
	if git merge-base --is-ancestor "$remote_sha" "$local_sha"; then
		die "local $branch has commits not on origin — push first, then deploy."
	fi
fi
ok "origin/$branch = ${remote_sha:0:12}"

# ── 2. Sync to origin ───────────────────────────────────────────────────
step "Syncing working tree to origin/$branch"
run git reset --hard "origin/$branch"
ok "reset to origin/$branch"

# ── 3. Build the new image ──────────────────────────────────────────────
# Before the backup and the stop: a build failure should cost nothing. The
# scheduler shares this image (healthee-api:latest), so one build covers both.
step "Building the api image"
run $COMPOSE build api
ok "built healthee-api:latest"

# ── 4. Backup — the point of no return is next ──────────────────────────
# 0004 rebuilds keys and 0005 drops a column, both on live health data. Going in
# without a fresh dump is not acceptable, so a failed backup aborts the deploy.
# `up -d db` (no force-recreate) is a no-op when db is already running and makes
# the dump possible on a cold box; pg_dump_backup.sh talks to the compose `db`
# service and reads POSTGRES_USER/DB + BACKUP_DIR from infra/.env itself.
step "Backing up the database"
run $COMPOSE up -d db
run "$backup_script" || die "backup FAILED — refusing to migrate without a fresh dump."
ok "backup written (see BACKUP_DIR in $env_file)"

# ── 5. Stop the app — the planned outage starts here ────────────────────
# Old code cannot serve the new schema (0004 keys / 0007 DEFAULT — see header),
# so these must be down BEFORE the schema moves. db stays up: it is what we are
# migrating.
step "Stopping api + scheduler (planned outage starts)"
run $COMPOSE stop api scheduler
ok "api + scheduler stopped"

# ── 6. Migrate ──────────────────────────────────────────────────────────
# `run --rm`, not `exec`: exec would need the api already up on the new image,
# which is exactly the window this ordering closes. The one-off container is
# built from the image we just built and connects as the admin/owner role
# (migrations are DDL; the app role deliberately has no CREATE/ALTER).
step "Applying pending migrations"
run $COMPOSE run --rm api python -m healthee.db.migrate ||
	die "migrations FAILED — api + scheduler are STOPPED. Do not start them: the schema is
  half-moved and old code cannot serve the new one either way. Read the error, fix
  forward, and re-run this script. Restore drill: infra/backup/RESTORE.md."
ok "migrations applied"

# ── 7. Provision the least-privilege app role ───────────────────────────
# Every deploy, idempotently — this is not a one-time step. A role provisioned by
# OLDER code lacks `timescaledb.enable_skipscan=off`, and without that setting
# /api/today 500s for every user under RLS (a TimescaleDB 2.26.4 planner bug; see
# db/provision_app_role.py). Re-provisioning is what keeps the role current, and
# it also un-drifts a role someone hand-altered.
#
# After migrate, so the tables it grants on exist. Skipped when the app creds are
# unset — the module exits non-zero without a password by design, and unset means
# the app is deliberately on the admin-cred fallback (MULTI_USER.md §3.3a).
step "Provisioning the app role"
if [ -n "${POSTGRES_APP_USER:-}" ] && [ -n "${POSTGRES_APP_PASSWORD:-}" ]; then
	run $COMPOSE run --rm api python -m healthee.db.provision_app_role ||
		die "provisioning the app role FAILED — api + scheduler are STOPPED. The app would
  start on stale or missing grants. Fix the cause and re-run; see MULTI_USER.md §3.3a."
	ok "app role '${POSTGRES_APP_USER}' provisioned/updated"
else
	warn "POSTGRES_APP_USER / POSTGRES_APP_PASSWORD not both set — skipping. The app will
    fall back to the ADMIN credentials, which BYPASS Row-Level Security. That is a
    transitional state, not a configuration: see infra/DEPLOY.md and MULTI_USER.md §3.3a."
fi

# ── 8. Recreate api + scheduler ─────────────────────────────────────────
# BOTH: since 6.4c the scheduler IS the per-user nightly chain sweep, it runs the
# same image, and it needs the same new env. Recreating only api would leave the
# old scheduler running old code against the new schema.
step "Recreating api + scheduler"
run $COMPOSE up -d --force-recreate api scheduler
ok "compose up"

# ── 8b. Verify the embedding index artifact (Step 2a hybrid retrieval) ──────
# NEVER --build here: the passage matrix is a COMMITTED artifact
# (packages/knowledge/embeddings/), built on a dev machine and checked in like the
# manifest, because this box's headroom cannot safely run the embedding pass (see
# insights/embedding_index.py's module docstring). --check is a hash comparison only
# (no model, no network) — WARN-ONLY: `insights/retrieval.py` falls back to
# explicit+lexical ranking if the artifact is ever missing/stale, so this never blocks
# a deploy, it just tells you the corpus moved without a re-commit.
step "Verifying the embedding index artifact"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ %s exec -T api python -m healthee.insights.embedding_index --check\033[0m\n' "$COMPOSE"
else
	if $COMPOSE exec -T api python -m healthee.insights.embedding_index --check; then
		ok "embedding index artifact matches the deployed corpus"
	else
		warn "embedding index artifact is stale or missing for this corpus — api/scheduler
    fall back to explicit+lexical ranking until it is rebuilt (this never blocks
    serving). On a dev machine: python -m healthee.insights.embedding_index --build,
    then commit packages/knowledge/embeddings/."
	fi
fi

# ── 9. Post-deploy healthcheck ──────────────────────────────────────────
step "Health check"
health_url="http://127.0.0.1:8765/healthz"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ curl -fsS %s   (polled until healthy, ~60s)\033[0m\n' "$health_url"
else
	healthy=0
	for attempt in $(seq 1 30); do
		if curl -fsS --max-time 3 "$health_url" >/dev/null 2>&1; then
			ok "healthy after ${attempt} attempt(s): $health_url"
			healthy=1
			break
		fi
		sleep 2
	done
	if [ "$healthy" -ne 1 ]; then
		printf '  \033[31m✗ health check FAILED\033[0m — %s did not respond in ~60s.\n' "$health_url" >&2
		printf '  Recent api logs:\n' >&2
		$COMPOSE logs --tail 40 api >&2 || true
		printf '  Recent scheduler logs:\n' >&2
		$COMPOSE logs --tail 20 scheduler >&2 || true
		exit 1
	fi
fi

# ── 9b. The edge, from outside ──────────────────────────────────────────
# 127.0.0.1:8765 answering proves the container is up; it proves nothing about
# nginx, DNS or the certificate, and those are what an owner's phone actually
# talks to. This is the check that used to be a curl pasted out of DEPLOY.md,
# which meant it was run when somebody remembered.
#
# A WARNING, never a failure: the app is up either way, and a lapsed certificate
# or a DNS change is not something this deploy did. Silence would be worse than
# both — it is how a working API sits behind a broken edge for a day.
step "Edge check (nginx → TLS → api)"
if [ -z "${PUBLIC_HOST:-}" ]; then
	warn "skipped — PUBLIC_HOST is not set."
elif [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ curl -fsS https://%s/healthz\033[0m\n' "$PUBLIC_HOST"
elif curl -fsS --max-time 10 "https://$PUBLIC_HOST/healthz" >/dev/null 2>&1; then
	ok "https://$PUBLIC_HOST/healthz answered"
else
	warn "https://$PUBLIC_HOST/healthz did NOT answer, but the container is healthy on
    127.0.0.1:8765. So the api is fine and something between it and the world is not:
    nginx down or misconfigured, DNS moved, or the certificate expired. Start with
    \`sudo nginx -t\` and \`sudo certbot certificates\`."
fi

# ── 10. Which DB role did the app actually connect as? ──────────────────
# The pool is lazy: it opens on the first query, and /healthz's `SELECT 1` is
# that query — so by the time the health check passed, core/db.py has logged
# exactly one of these two lines. Asked of the running app rather than inferred
# from the env, because only the server knows what the role really is.
#
# The BYPASSRLS warning does NOT fail the deploy: the admin-cred fallback is a
# legitimate transitional state (§3.3a) and the app is serving. But it never
# passes silently either — RLS protecting nothing must be visible to whoever ran
# this.
step "Verifying the DB identity the app pool connected as"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ %s logs --tail 200 api | grep -E "least-privilege role|BYPASSES Row-Level Security"\033[0m\n' "$COMPOSE"
else
	api_logs="$($COMPOSE logs --tail 200 api 2>/dev/null || true)"
	if printf '%s\n' "$api_logs" | grep -q 'connected as least-privilege role'; then
		ok "RLS is real — the pool is on the least-privilege role (NOSUPERUSER NOBYPASSRLS)."
	elif printf '%s\n' "$api_logs" | grep -q 'BYPASSES Row-Level Security'; then
		warn "The app pool is on a role that BYPASSES Row-Level Security (the admin-cred
    fallback). The deploy is HEALTHY and this is not fatal — but RLS is isolating
    nothing until POSTGRES_APP_USER / POSTGRES_APP_PASSWORD are set. Next steps:
    infra/DEPLOY.md → 'The credential order'."
	else
		warn "Could not find either DB-role line in the last 200 api log lines. The pool may
    not have opened yet, or logging changed. Check by hand:
    $COMPOSE logs api | grep -i 'db pool'"
	fi
fi

if [ "$dry_run" -eq 1 ]; then
	step "DRY RUN complete — nothing was changed"
else
	step "Deploy OK"
fi
exit 0
