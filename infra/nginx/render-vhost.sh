#!/usr/bin/env bash
# infra/nginx/render-vhost.sh — the vhost, with YOUR host substituted in.
#
#   infra/nginx/render-vhost.sh             # print it; change nothing
#   infra/nginx/render-vhost.sh --install   # write it and enable it (needs sudo)
#
# `PUBLIC_HOST` comes from `infra/.env`, the same file the deploy already reads,
# or from the environment if you would rather pass it inline. That indirection is
# the point: deploying should never mean editing a tracked file, and no operator's
# own domain should end up in this repository.
#
# ⛔ `--install` REFUSES to overwrite a vhost that already has a 443 listener.
# certbot rewrites the installed file in place, so the live vhost is certbot's and
# this template is the pre-certbot :80 one — re-rendering over it would delete the
# TLS block and the redirect, and nginx would come back serving plain HTTP. That
# is also why `deploy.sh` never touches nginx: a code deploy has no business
# rewriting the edge.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
template="$script_dir/healtheeapi.conf.template"
env_file="$script_dir/../.env"

install=0
[ "${1:-}" = "--install" ] && install=1
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
fi

[ -f "$template" ] || {
	echo "template not found: $template" >&2
	exit 1
}

# The environment wins over the file, so a one-off render needs no edit at all.
if [ -z "${PUBLIC_HOST:-}" ] && [ -f "$env_file" ]; then
	set -a
	# shellcheck source=/dev/null
	. "$env_file"
	set +a
fi

if [ -z "${PUBLIC_HOST:-}" ]; then
	echo "PUBLIC_HOST is not set. Add it to infra/.env (see .env.example) or pass it:" >&2
	echo "  PUBLIC_HOST=api.example.com $0" >&2
	exit 1
fi

# A host, not a URL and not a host:port. Caught here rather than by nginx at
# reload time, when the site is already down.
case "$PUBLIC_HOST" in
*://* | */* | *:*)
	echo "PUBLIC_HOST must be a bare hostname, not '$PUBLIC_HOST'" >&2
	exit 1
	;;
esac

# Only PUBLIC_HOST is substituted. Plain `envsubst` would also eat nginx's own
# runtime variables — $binary_remote_addr, $host, $remote_addr — and render a
# vhost that silently rate-limits every client as one.
rendered="$(PUBLIC_HOST="$PUBLIC_HOST" envsubst '${PUBLIC_HOST}' <"$template")"

if [ "$install" -eq 0 ]; then
	printf '%s\n' "$rendered"
	exit 0
fi

target="/etc/nginx/sites-available/$PUBLIC_HOST"
if [ -f "$target" ] && grep -qE '^\s*listen\s+443' "$target"; then
	echo "REFUSING to overwrite $target — it already has a 443 listener." >&2
	echo "That file is certbot's, and this template is the pre-certbot :80 one." >&2
	echo "Overwriting it would remove the TLS block. Edit it by hand, or move it aside" >&2
	echo "deliberately and re-run certbot afterwards." >&2
	exit 1
fi

printf '%s\n' "$rendered" | sudo tee "$target" >/dev/null
sudo ln -sfn "$target" "/etc/nginx/sites-enabled/$PUBLIC_HOST"
sudo nginx -t
echo "Wrote $target and enabled it. Now: sudo systemctl reload nginx"
echo "First time only, for TLS:   sudo certbot --nginx -d $PUBLIC_HOST"
