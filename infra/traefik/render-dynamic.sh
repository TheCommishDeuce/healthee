#!/usr/bin/env bash
# infra/traefik/render-dynamic.sh — the Traefik dynamic config, with YOUR values in.
#
#   infra/traefik/render-dynamic.sh              # print it; change nothing
#   infra/traefik/render-dynamic.sh --install    # write it to the watched dir
#
# Follows `infra/nginx/render-vhost.sh`, for the same reason: nobody should edit a
# tracked file to deploy, and no operator's domain or private IP should land in this
# repository. The values come from the Dockge stack's `.env`, which is where every
# other deployment-specific value already lives.
#
# ── Run this on the TRAEFIK host ───────────────────────────────────────────
#
# Which is not the host running the stack, and that is the whole point of this
# script existing. Two ways to get the values across:
#
#   a. a checkout on the Traefik host, with the three values passed inline:
#        PUBLIC_HOST=api.example.com HEALTHEE_BIND_ADDR=10.0.0.5 \
#          infra/traefik/render-dynamic.sh --install
#
#   b. render on the Healthee box (where .env already is) and copy the result:
#        infra/traefik/render-dynamic.sh | ssh traefik-host \
#          'sudo tee /etc/traefik/dynamic/healthee.yml >/dev/null'
#
# Traefik with `watch: true` reloads on save — no restart, no dropped connections.

set -eu

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
template="$script_dir/healthee.yml.template"
# The Dockge stack's env is the source of truth for both values. Overridable for
# the case where this runs on a box that has no copy of it.
env_file="${HEALTHEE_ENV_FILE:-${HEALTHEE_STACK_DIR:-/opt/stacks/healthee}/.env}"
# WHERE to install. Two shapes, because Traefik's file provider takes either.
#   TRAEFIK_DYNAMIC_FILE  an exact path      -> use with `directory:` providers
#   TRAEFIK_DYNAMIC_DIR   a directory        -> healthee.yml is written inside it
# A `filename:` provider pointing at one shared config.yml CANNOT take a second
# file; --install refuses that case rather than writing something never read.
target_dir="${TRAEFIK_DYNAMIC_DIR:-/etc/traefik/dynamic}"
target_file="${TRAEFIK_DYNAMIC_FILE:-}"

install=0
for arg in "$@"; do
	case "$arg" in
	--install) install=1 ;;
	-h | --help)
		sed -n '2,28p' "$0"
		exit 0
		;;
	*)
		echo "unknown argument: $arg (try --help)" >&2
		exit 1
		;;
	esac
done

[ -f "$template" ] || {
	echo "template not found: $template" >&2
	exit 1
}

# ⛔ READ, never SOURCE. An operator's .env is not a shell script: an unquoted value
# containing a space runs its second word as a command, and the shipped template had
# exactly that. Same helper as infra/dockge/deploy.sh, same reason.
env_get() {
	[ -f "$env_file" ] || return 0
	sed -n "s/^[[:space:]]*$1=//p" "$env_file" | tail -n1 |
		sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# The environment wins over the file, so a one-off render on a box with no stack
# needs no edit at all — see (a) in the header.
PUBLIC_HOST="${PUBLIC_HOST:-$(env_get PUBLIC_HOST)}"
HEALTHEE_BIND_ADDR="${HEALTHEE_BIND_ADDR:-$(env_get HEALTHEE_BIND_ADDR)}"
TRAEFIK_IP_DEPTH="${TRAEFIK_IP_DEPTH:-$(env_get TRAEFIK_IP_DEPTH)}"
TRAEFIK_IP_DEPTH="${TRAEFIK_IP_DEPTH:-0}"

die_missing() {
	echo "$1 is not set. Add it to $env_file, or pass it inline:" >&2
	echo "  PUBLIC_HOST=api.example.com HEALTHEE_BIND_ADDR=10.0.0.5 $0 --install" >&2
	exit 1
}
[ -n "$PUBLIC_HOST" ] || die_missing PUBLIC_HOST
[ -n "$HEALTHEE_BIND_ADDR" ] || die_missing HEALTHEE_BIND_ADDR

# A host, not a URL and not a host:port. Caught here rather than by Traefik at
# reload time, when a bad Host() rule means the router silently matches nothing.
case "$PUBLIC_HOST" in
*://* | */* | *:*)
	echo "PUBLIC_HOST must be a bare hostname, not '$PUBLIC_HOST'" >&2
	exit 1
	;;
esac

# ⛔ The one check that catches the mistake this whole split-host setup invites.
# 127.0.0.1 is what the same-host setup used and what a half-copied runbook leaves
# behind; on the Traefik host it means "dial myself", so Traefik would proxy to its
# own port 8765 and serve a connection refused that names nothing.
case "$HEALTHEE_BIND_ADDR" in
127.* | localhost | ::1)
	echo "HEALTHEE_BIND_ADDR is '$HEALTHEE_BIND_ADDR', which on the Traefik host means" >&2
	echo "Traefik itself, not the Healthee box. Use the Healthee box's PRIVATE ip." >&2
	exit 1
	;;
0.0.0.0 | "")
	echo "HEALTHEE_BIND_ADDR must be the Healthee box's PRIVATE ip, not '$HEALTHEE_BIND_ADDR'." >&2
	exit 1
	;;
*://*)
	echo "HEALTHEE_BIND_ADDR is an address, not a URL: '$HEALTHEE_BIND_ADDR'" >&2
	exit 1
	;;
esac

# Only these three are substituted, by name. Plain `envsubst` with no list would
# also eat anything else that looks like a variable.
rendered="$(
	PUBLIC_HOST="$PUBLIC_HOST" \
		HEALTHEE_BIND_ADDR="$HEALTHEE_BIND_ADDR" \
		TRAEFIK_IP_DEPTH="$TRAEFIK_IP_DEPTH" \
		envsubst '${PUBLIC_HOST} ${HEALTHEE_BIND_ADDR} ${TRAEFIK_IP_DEPTH}' <"$template"
)"

if [ "$install" -eq 0 ]; then
	printf '%s\n' "$rendered"
	exit 0
fi

if [ -n "$target_file" ]; then
	target="$target_file"
	target_dir="$(dirname "$target")"
else
	target="$target_dir/healthee.yml"
fi

[ -d "$target_dir" ] || {
	echo "Traefik's dynamic directory does not exist: $target_dir" >&2
	echo "Create it and point the file provider at it, or set TRAEFIK_DYNAMIC_DIR /" >&2
	echo "TRAEFIK_DYNAMIC_FILE. See infra/traefik/CHECKLIST.md §0." >&2
	exit 1
}

# ⛔ Refuse to clobber somebody else's dynamic config.
#
# A single shared `config.yml` holding several apps' routers is a common Traefik
# setup, and it is the one shape this script must not write to: it would replace
# every other app's routing with ours. Detected by looking for routers we did not
# put there. The fix is the directory provider (CHECKLIST §0) — not a bigger script.
if [ -f "$target" ] && grep -qE '^\s{0,6}[a-zA-Z0-9_-]+:' "$target" &&
	grep -q 'routers:' "$target" && ! grep -q 'healthee:' "$target"; then
	echo "REFUSING to overwrite $target — it already contains routers that are not ours." >&2
	echo >&2
	echo "That looks like a shared dynamic config. Overwriting it would delete every" >&2
	echo "other app's routing on this host. Switch the file provider to a directory:" >&2
	echo >&2
	echo "  providers:" >&2
	echo "    file:" >&2
	echo "      directory: /etc/traefik/dynamic   # was: filename: $target" >&2
	echo "      watch: true" >&2
	echo >&2
	echo "then move your existing file into it and re-run. Traefik merges every file" >&2
	echo "in the directory, so nothing is lost and each app owns its own." >&2
	exit 1
fi
printf '%s\n' "$rendered" | sudo tee "$target" >/dev/null
echo "Wrote $target"
echo
echo "With \`watch: true\` Traefik has already reloaded. Confirm the router is up:"
echo "  curl -s http://127.0.0.1:8080/api/http/routers/healthee@file | head"
echo "and then, from anywhere:"
echo "  curl -fsS https://$PUBLIC_HOST/healthz"
echo
echo "Unused repo path note: $repo_root is only the source of the template."
