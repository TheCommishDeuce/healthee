#!/usr/bin/env bash
# infra/dockge/deploy.sh — the schema-safe deploy for the Dockge + Traefik stack.
#
# Run it from Dockge's own terminal tab for the stack, or over ssh:
#   <repo>/infra/dockge/deploy.sh              # deploy
#   <repo>/infra/dockge/deploy.sh --dry-run    # print the plan, change nothing
#
# ── When do I need this instead of Dockge's update button? ─────────────────
#
# The button (`compose pull` + `up -d`) is CORRECT for a code-only release, and the
# `preflight` service is what proves the release is one. Use the button by default.
#
# You need this script when the preflight REFUSES the update — because the release
# carries a schema change. Only this path takes a backup first and only this path
# stops the app before the schema moves. The preflight's error message sends you here.
#
# ⚠ THE STOP → MIGRATE → START WINDOW IS A DELIBERATE, PLANNED OUTAGE.
# Our migrations are NOT backwards-compatible: 0004 folds `user_id` into the natural
# keys (old code's `ON CONFLICT (day, metric)` then matches no constraint) and 0007
# drops the `user_id` DEFAULT (old owner-less INSERTs become NotNullViolation). Old
# code CANNOT serve the new schema, so there is no zero-downtime path; leaving the
# containers up would only mean erroring mid-write instead of being honestly down.
#
# ── What it does ───────────────────────────────────────────────────────────
#   1. Preflight; verify the branch is pushed (the VPS deploys origin's version).
#   2. git fetch && git reset --hard origin/<branch>.
#   3. Sync compose.yaml from the repo into the stack dir, showing any diff.
#   4. docker compose pull — fetch the image CI published.
#   5. BACKUP the database. Abort on failure: the migrations run on live data.
#   6. STOP api + scheduler.
#   7. MIGRATE on the new image, while db stays up.
#   8. PROVISION the least-privilege app role (idempotent, every deploy).
#   9. up -d — the preflight re-runs here and must now pass.
#  10. Health check, edge check, and which DB role the pool actually connected as.
#
# The stack directory defaults to /opt/stacks/healthee (Dockge's layout). Override:
#   HEALTHEE_STACK_DIR=/srv/stacks/healthee <repo>/infra/dockge/deploy.sh

set -euo pipefail

# ── Locate the repo and the stack ───────────────────────────────────────
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
stack_dir="${HEALTHEE_STACK_DIR:-/opt/stacks/healthee}"
env_file="$stack_dir/.env"
backup_script="$repo_root/infra/backup/pg_dump_backup.sh"

# ── UI helpers ──────────────────────────────────────────────────────────
step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠ %s\033[0m\n' "$1" >&2; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
	cat <<'EOF'
Usage: infra/dockge/deploy.sh [--dry-run]

  --dry-run   Print every command this deploy would run, in order — and change
              nothing. This script takes prod down; use this first.
  -h, --help  Show this help.

Env:
  HEALTHEE_STACK_DIR   the Dockge stack directory (default /opt/stacks/healthee)
EOF
}

dry_run=0
for arg in "$@"; do
	case "$arg" in
	--dry-run) dry_run=1 ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $arg (try --help)" ;;
	esac
done

# Run a command, or (in --dry-run) print exactly what would have run. Read-only
# inspection is not routed through this — it is what resolves the plan we print.
run() {
	if [ "$dry_run" -eq 1 ]; then
		printf '  \033[2m$ %s\033[0m\n' "$*"
		return 0
	fi
	"$@"
}

# ── Preflight ───────────────────────────────────────────────────────────
step "Preflight"
command -v docker >/dev/null 2>&1 || die "docker not found"
[ -d "$stack_dir" ] || die "stack dir not found: $stack_dir
    Dockge keeps stacks in /opt/stacks/<name>. Set HEALTHEE_STACK_DIR if yours differs."
[ -f "$env_file" ] || die "env file not found: $env_file
    Copy infra/dockge/.env.example there and fill it in (or create the stack in Dockge first)."
[ -x "$backup_script" ] || die "backup script not found or not executable: $backup_script"

# ⛔ The env file is READ, never SOURCED. `set -a; . "$env_file"` executes it, and an
# operator's `.env` is not a shell script: an unquoted value containing a space runs
# its second word as a command. The shipped template had exactly that
# (`MAP_TILE_ATTRIBUTION=© OpenStreetMap contributors`), so copying it verbatim and
# running the deploy aborted at this line with `OpenStreetMap: command not found`.
# Quoting the template fixes that one value; not executing the file fixes the class.
env_get() {
	sed -n "s/^[[:space:]]*$1=//p" "$env_file" | tail -n1 |
		sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

branch="$(env_get DEPLOY_BRANCH)"
branch="${branch:-main}"
PUBLIC_HOST="$(env_get PUBLIC_HOST)"
POSTGRES_APP_USER="$(env_get POSTGRES_APP_USER)"
POSTGRES_APP_PASSWORD="$(env_get POSTGRES_APP_PASSWORD)"
HEALTHEE_BIND_ADDR="$(env_get HEALTHEE_BIND_ADDR)"
HEALTHEE_IMAGE="$(env_get HEALTHEE_IMAGE)"
HEALTHEE_IMAGE_TAG="$(env_get HEALTHEE_IMAGE_TAG)"
HEALTHEE_BUILD_LOCALLY="$(env_get HEALTHEE_BUILD_LOCALLY)"
ok "stack dir:     $stack_dir"
ok "deploy branch: $branch"
if [ -n "${PUBLIC_HOST:-}" ]; then
	ok "public host:   $PUBLIC_HOST"
else
	warn "PUBLIC_HOST is not set in $env_file — the edge check will be skipped, and
    Traefik has no Host() rule to route on, so the site is not reachable at all."
fi
# Not `[ … ] && ok …`: that compound's status is the test's, and a reader who later
# moves this line to the end of a block gets a script that exits 1 having done
# everything right. The long form cannot acquire that bug.
if [ "$dry_run" -eq 1 ]; then
	ok "DRY RUN — nothing below will be executed"
fi

# Everything below runs from the stack dir so `docker compose` resolves the SAME
# project Dockge does (compose derives the project name from this directory). Using
# `-f /path/to/compose.yaml` from elsewhere can address a differently-named project
# and leave you operating on containers nobody else can see.
cd "$stack_dir"

# ── 1. Verify local == origin (the push-before-deploy guard) ────────────
step "Verifying $branch is pushed"
git -C "$repo_root" fetch --quiet origin "$branch" || die "git fetch failed for origin/$branch"
local_sha="$(git -C "$repo_root" rev-parse "$branch" 2>/dev/null || echo "")"
remote_sha="$(git -C "$repo_root" rev-parse "origin/$branch")"
if [ -n "$local_sha" ] && [ "$local_sha" != "$remote_sha" ]; then
	# Only abort if local is AHEAD: unpushed commits would be lost by the reset.
	# Behind or diverged is fine — we deploy origin's version anyway.
	if git -C "$repo_root" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
		die "local $branch has commits not on origin — push first, then deploy."
	fi
fi
ok "origin/$branch = ${remote_sha:0:12}"

# ── 2. Sync the checkout ────────────────────────────────────────────────
step "Syncing the repo checkout to origin/$branch"
run git -C "$repo_root" reset --hard "origin/$branch"
ok "reset to origin/$branch"

# ── 3. Sync compose.yaml into the stack dir ─────────────────────────────
# The image is versioned by its tag, but compose.yaml is not in the image — Dockge
# reads its own copy here. A release that adds a service or a volume would otherwise
# be invisible to the box no matter how many times anyone pressed update.
#
# The diff is PRINTED rather than applied silently: this file is editable from
# Dockge's UI, so a difference may be a deliberate local change about to be
# overwritten, and that should be seen by whoever is running the deploy.
step "Syncing compose.yaml into the stack"
tracked_compose="$repo_root/infra/dockge/compose.yaml"
[ -f "$tracked_compose" ] || die "tracked compose file missing: $tracked_compose"
if [ -f compose.yaml ] && diff -q compose.yaml "$tracked_compose" >/dev/null 2>&1; then
	ok "compose.yaml already matches the repo"
else
	if [ -f compose.yaml ]; then
		warn "the stack's compose.yaml differs from the repo — it will be REPLACED:"
		diff -u compose.yaml "$tracked_compose" | sed 's/^/    /' || true
		run cp compose.yaml "compose.yaml.bak.$(date +%Y%m%d%H%M%S)"
	fi
	run cp "$tracked_compose" compose.yaml
	ok "compose.yaml updated from the repo (previous copy kept as .bak.<timestamp>)"
fi

# ── 4. Obtain the new image ────────────────────────────────────────
# Before the backup and the stop: a failure here should cost nothing. All three app
# services share one image reference, so this covers them.
#
# Two ways to have an image, and which one applies is a deployment fact rather than
# a property of the code — so it lives in .env, not in this script's logic.
image_ref="${HEALTHEE_IMAGE:-ghcr.io/afkcodes/healthee-api}:${HEALTHEE_IMAGE_TAG:-main}"
if [ "${HEALTHEE_BUILD_LOCALLY:-false}" = "true" ]; then
	# No registry to publish to. The build context is the REPO ROOT — the Dockerfile
	# copies apps/server/* and packages/knowledge from there — which is why the
	# checkout exists on the box at all, and why this cannot run from the stack dir.
	#
	# ⚠ Dockge's update button only PULLS. With this set it can never obtain a new
	# image, so every update has to come through this script.
	step "Building the image locally"
	run docker build \
		--file "$repo_root/infra/docker/Dockerfile.server" \
		--tag "$image_ref" \
		"$repo_root" || die "build FAILED — nothing changed; the running stack is untouched."
	ok "built $image_ref"
else
	step "Pulling the image"
	run docker compose pull ||
		die "pull FAILED for $image_ref — nothing changed; the running stack is untouched.
  'denied' or 'manifest unknown' usually means one of: the package is private and this
  box has never run \`docker login ghcr.io\`; HEALTHEE_IMAGE names a namespace you do
  not publish to; or CI has not built this tag yet. To build on this box instead, set
  HEALTHEE_BUILD_LOCALLY=true in $env_file."
	ok "pulled $image_ref"
fi

# ── 5. Backup — the point of no return is next ──────────────────────────
# `up -d db` (no force-recreate) is a no-op when db is already running and makes the
# dump possible on a cold box.
step "Backing up the database"
run docker compose up -d db
run "$backup_script" || die "backup FAILED — refusing to migrate without a fresh dump."
ok "backup written (see BACKUP_DIR in $env_file)"

# ── 6. Stop the app — the planned outage starts here ────────────────────
step "Stopping api + scheduler (planned outage starts)"
run docker compose stop api scheduler
ok "api + scheduler stopped"

# ── 7. Migrate ──────────────────────────────────────────────────────────
# `run --rm`, not `exec`: exec would need the api already up on the new image, which
# is exactly the window this ordering closes. The one-off container connects as the
# admin/owner role — migrations are DDL, and the app role deliberately has no
# CREATE or ALTER.
#
# `--no-deps` so compose does not try to satisfy the api's `preflight` dependency
# here. The preflight's whole job is to REFUSE while migrations are pending, which
# is precisely the state we are in at this line.
step "Applying pending migrations"
run docker compose run --rm --no-deps api python -m healthee.db.migrate ||
	die "migrations FAILED — api + scheduler are STOPPED. Do not start them: the schema is
  half-moved and old code cannot serve the new one either way. Read the error, fix
  forward, and re-run this script. Restore drill: infra/backup/RESTORE.md."
ok "migrations applied"

# ── 8. Provision the least-privilege app role ───────────────────────────
# Every deploy, idempotently — not a one-time step. A role provisioned by OLDER code
# lacks `timescaledb.enable_skipscan=off`, and without it /api/today 500s for every
# user under RLS (a TimescaleDB 2.26.4 planner bug). Re-provisioning keeps the role
# current and un-drifts one somebody hand-altered. After migrate, so its tables exist.
step "Provisioning the app role"
if [ -n "${POSTGRES_APP_USER:-}" ] && [ -n "${POSTGRES_APP_PASSWORD:-}" ]; then
	run docker compose run --rm --no-deps api python -m healthee.db.provision_app_role ||
		die "provisioning the app role FAILED — api + scheduler are STOPPED. The app would
  start on stale or missing grants. Fix the cause and re-run; see MULTI_USER.md §3.3a."
	ok "app role '${POSTGRES_APP_USER}' provisioned/updated"
else
	warn "POSTGRES_APP_USER / POSTGRES_APP_PASSWORD not both set — skipping. The app will
    fall back to the ADMIN credentials, which BYPASS Row-Level Security. That is a
    transitional state, not a configuration: see infra/DEPLOY.md and MULTI_USER.md §3.3a."
fi

# ── 9. Bring the stack back up ──────────────────────────────────────────
# The preflight runs again here, on the image we just migrated for. It must pass
# now — if it does not, something applied less than it reported and the containers
# stay down rather than serving a schema they do not match.
step "Recreating api + scheduler"
run docker compose up -d --force-recreate api scheduler
ok "compose up"

# ── 9b. Verify the embedding index artifact ─────────────────────────────
# The passage matrix is a COMMITTED artifact (packages/knowledge/embeddings/), built
# on a dev machine because this box's headroom cannot safely run the embedding pass.
# `--check` is a hash comparison only (no model, no network) and is WARN-ONLY:
# retrieval falls back to explicit+lexical ranking if it is stale, so this never
# blocks a deploy — it just tells you the corpus moved without a re-commit.
step "Verifying the embedding index artifact"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ docker compose exec -T api python -m healthee.insights.embedding_index --check\033[0m\n'
elif docker compose exec -T api python -m healthee.insights.embedding_index --check; then
	ok "embedding index artifact matches the deployed corpus"
else
	warn "embedding index artifact is stale or missing — api/scheduler fall back to
    explicit+lexical ranking until it is rebuilt (this never blocks serving). On a dev
    machine: python -m healthee.insights.embedding_index --build, then commit
    packages/knowledge/embeddings/."
fi

# ── 10. Health check ────────────────────────────────────────────────────
# From INSIDE the container: this stack publishes no host port, because Traefik
# reaches the api on the proxy network and nothing else should be able to.
step "Health check"
probe='import urllib.request; urllib.request.urlopen("http://localhost:8765/healthz", timeout=3)'
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ docker compose exec -T api python -c "<GET /healthz>"   (polled, ~60s)\033[0m\n'
else
	healthy=0
	for attempt in $(seq 1 30); do
		if docker compose exec -T api python -c "$probe" >/dev/null 2>&1; then
			ok "healthy after ${attempt} attempt(s)"
			healthy=1
			break
		fi
		sleep 2
	done
	if [ "$healthy" -ne 1 ]; then
		printf '  \033[31m✗ health check FAILED\033[0m — /healthz did not answer in ~60s.\n' >&2
		printf '  Recent preflight logs (it gates the api — start here):\n' >&2
		docker compose logs --tail 20 preflight >&2 || true
		printf '  Recent api logs:\n' >&2
		docker compose logs --tail 40 api >&2 || true
		printf '  Recent scheduler logs:\n' >&2
		docker compose logs --tail 20 scheduler >&2 || true
		exit 1
	fi
fi

# ── 10b. Where is the port actually bound? ────────────────────────────
# Asked of Docker rather than of .env, because only Docker knows what it actually
# did. A 0.0.0.0 bind puts an API whose only check is a bearer token on the public
# internet with no TLS and no rate limit — and `ufw deny` does NOT close it, because
# Docker's iptables rules run first. This is the one misconfiguration in this
# topology that is silent, remote, and about health records.
step "Checking where the api port is bound"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ docker compose port api 8765\033[0m\n'
else
	bound="$(docker compose port api 8765 2>/dev/null || true)"
	case "$bound" in
	0.0.0.0:* | "[::]:"*)
		warn "⛔ THE API IS PUBLISHED ON ALL INTERFACES ($bound).
    It is reachable from the public internet with no TLS, no rate limit and a bearer
    token as the only protection. A ufw rule will NOT fix this — Docker's iptables
    rules are evaluated first. Set HEALTHEE_BIND_ADDR to this box's PRIVATE ip in
    $env_file and redeploy. Verify from OFF this network:
      curl --max-time 5 http://<this-box-public-ip>:8765/healthz    # must FAIL"
		;;
	127.*)
		warn "the api is bound to loopback ($bound), so the Traefik host cannot reach it.
    The stack is healthy and the site will 502. Set HEALTHEE_BIND_ADDR to this box's
    private ip in $env_file and redeploy."
		;;
	"")
		warn "could not determine the api's published port (is it running?)."
		;;
	*)
		ok "bound to $bound — private interface only"
		;;
	esac
fi

# ── 10c. The edge, from outside ─────────────────────────────────────────
# The container answering proves nothing about Traefik, DNS or the certificate, and
# those are what an owner's phone actually talks to.
#
# A WARNING, never a failure: the app is up either way, and a lapsed certificate or
# a DNS change is not something this deploy did. Silence would be worse than both —
# it is how a working API sits behind a broken edge for a day.
step "Edge check (Traefik → TLS → api)"
if [ -z "${PUBLIC_HOST:-}" ]; then
	warn "skipped — PUBLIC_HOST is not set."
elif [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ curl -fsS https://%s/healthz\033[0m\n' "$PUBLIC_HOST"
elif curl -fsS --max-time 10 "https://$PUBLIC_HOST/healthz" >/dev/null 2>&1; then
	ok "https://$PUBLIC_HOST/healthz answered"
else
	warn "https://$PUBLIC_HOST/healthz did NOT answer, but the container is healthy. So
    the api is fine and something between it and the world is not. In order of how
    often it is the cause:
      1. Traefik cannot reach this box  — from the TRAEFIK host:
                                          curl -sS http://${HEALTHEE_BIND_ADDR:-<private-ip>}:8765/healthz
      2. the dynamic config is stale    — re-run infra/traefik/render-dynamic.sh there
      3. the certificate was never issued — DNS must resolve to the TRAEFIK host
                                          BEFORE ACME can work
      4. DNS moved."
fi

# ── 11. Which DB role did the app actually connect as? ──────────────────
# The pool is lazy: it opens on the first query, and /healthz's `SELECT 1` is that
# query — so by now core/db.py has logged exactly one of these two lines. Asked of
# the running app rather than inferred from the env, because only the server knows.
step "Verifying the DB identity the app pool connected as"
if [ "$dry_run" -eq 1 ]; then
	printf '  \033[2m$ docker compose logs --tail 200 api | grep -E "least-privilege role|BYPASSES Row-Level Security"\033[0m\n'
else
	api_logs="$(docker compose logs --tail 200 api 2>/dev/null || true)"
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
    docker compose logs api | grep -i 'db pool'"
	fi
fi

if [ "$dry_run" -eq 1 ]; then
	step "DRY RUN complete — nothing was changed"
else
	step "Deploy OK"
fi
exit 0
