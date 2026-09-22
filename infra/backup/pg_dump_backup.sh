#!/usr/bin/env bash
# infra/backup/pg_dump_backup.sh — dated, gzipped Postgres backup for Healthee.
#
# Dumps the compose `db` service with pg_dump, gzips to a dated file, prunes
# dumps older than BACKUP_RETENTION_DAYS, and (optionally) ships a copy off-box.
# Designed to run from healthee-backup.timer, but safe to run by hand.
#
# Exits non-zero with a clear message on any failure (so the systemd unit and
# any log watcher can alert). Restore drill: see infra/backup/RESTORE.md.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
infra_dir="$(cd "$script_dir/.." && pwd)"
# Which stack to dump. The defaults are the nginx-topology stack this script was
# written for; the Dockge stack lives in a directory outside the repo and passes
# both by environment (infra/dockge/deploy.sh exports them).
#
# This is not a nicety: pointed at the wrong compose file, `compose exec db` either
# fails outright or — worse — addresses a DIFFERENT project's database and writes a
# dump of the wrong data under a name that says it is the right one.
compose_file="${HEALTHEE_COMPOSE_FILE:-$infra_dir/docker/docker-compose.prod.yml}"
env_file="${HEALTHEE_ENV_FILE:-$infra_dir/.env}"

die() { printf 'pg_dump_backup: ERROR — %s\n' "$1" >&2; exit 1; }

[ -f "$env_file" ] || die "env file not found: $env_file"
[ -f "$compose_file" ] || die "compose file not found: $compose_file"

set -a
# shellcheck source=/dev/null
. "$env_file"
set +a

: "${POSTGRES_USER:?POSTGRES_USER not set in $env_file}"
: "${POSTGRES_DB:?POSTGRES_DB not set in $env_file}"
backup_dir="${BACKUP_DIR:-/var/backups/healthee}"
retention_days="${BACKUP_RETENTION_DAYS:-30}"

mkdir -p "$backup_dir" || die "cannot create backup dir: $backup_dir"

stamp="$(date +%Y-%m-%d_%H%M%S)"
dump_file="$backup_dir/healthee_${stamp}.sql.gz"
tmp_file="${dump_file}.partial"

COMPOSE="docker compose --env-file $env_file -f $compose_file"

# ── Dump ────────────────────────────────────────────────────────────────
# -T: no TTY (cron-safe). pg_dump streams to stdout; gzip on the host.
# On any failure in the pipeline, remove the partial and abort.
if ! $COMPOSE exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
	| gzip -c > "$tmp_file"; then
	rm -f "$tmp_file"
	die "pg_dump/gzip failed — no backup written."
fi

# A valid gzip of an empty dump is still suspicious; guard against 0-byte files.
if [ ! -s "$tmp_file" ]; then
	rm -f "$tmp_file"
	die "backup produced an empty file — aborting."
fi

mv "$tmp_file" "$dump_file"
size="$(du -h "$dump_file" | cut -f1)"
printf 'pg_dump_backup: wrote %s (%s)\n' "$dump_file" "$size"

# ── Off-box copy (optional) ─────────────────────────────────────────────
if [ -n "${OFFBOX_CMD:-}" ]; then
	# Replace the literal {} in OFFBOX_CMD with the dump path.
	offbox="${OFFBOX_CMD//\{\}/$dump_file}"
	if sh -c "$offbox"; then
		printf 'pg_dump_backup: off-box copy OK\n'
	else
		die "off-box copy failed (OFFBOX_CMD). Local backup is kept at $dump_file."
	fi
fi

# ── Prune old dumps ─────────────────────────────────────────────────────
pruned="$(find "$backup_dir" -name 'healthee_*.sql.gz' -type f \
	-mtime "+${retention_days}" -print -delete | wc -l | tr -d ' ')"
printf 'pg_dump_backup: pruned %s dump(s) older than %s days\n' "$pruned" "$retention_days"

printf 'pg_dump_backup: OK\n'
