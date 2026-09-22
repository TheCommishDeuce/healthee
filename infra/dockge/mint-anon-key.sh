#!/usr/bin/env bash
# infra/dockge/mint-anon-key.sh — the `anon` key, for a SELF-HOSTED GoTrue.
#
#   infra/dockge/mint-anon-key.sh                    # reads SUPABASE_JWT_SECRET from .env
#   SUPABASE_JWT_SECRET=… infra/dockge/mint-anon-key.sh
#
# ## Why this exists
#
# Hosted Supabase hands you an anon key on a dashboard. A self-hosted GoTrue does
# not: the anon key is simply a JWT with `role: anon`, signed with the same
# `GOTRUE_JWT_SECRET` the server verifies against. There is no other source for it,
# so it is minted here.
#
# ## Why a non-empty value is REQUIRED even though GoTrue ignores it
#
# Standalone GoTrue does not read the `apikey` header at all — that is Kong's job in
# the full hosted stack. But the APP refuses to treat a config as usable when the key
# is empty (`auth_config.dart`: `key.isEmpty` ⇒ no provider), and the server serves
# both fields or neither. So an empty anon key means a sign-in screen that never
# appears, with nothing in any log to say why.
#
# A real signed JWT rather than a placeholder string: it costs nothing, it is what
# hosted Supabase sends, and it keeps working if a gateway is ever put in front.
#
# ⚠ This key is PUBLIC by construction — it ships inside the app and authorises
# nothing on its own. The SECRET it is signed with is not; never print that.
#
# Openssl only. No python, no jq, nothing to install on the box.

set -euo pipefail

stack_dir="${HEALTHEE_STACK_DIR:-/opt/stacks/healthee}"
env_file="${HEALTHEE_ENV_FILE:-$stack_dir/.env}"

# Read, never source — an operator's .env is not a shell script.
env_get() {
	[ -f "$env_file" ] || return 0
	sed -n "s/^[[:space:]]*$1=//p" "$env_file" | tail -n1 |
		sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

secret="${SUPABASE_JWT_SECRET:-$(env_get SUPABASE_JWT_SECRET)}"
if [ -z "$secret" ]; then
	echo "SUPABASE_JWT_SECRET is not set (looked in $env_file)." >&2
	echo "Generate one first:  openssl rand -base64 48 | tr -d '/+=' | head -c 64" >&2
	exit 1
fi

# GoTrue refuses to start on a trivially short secret, and so should this.
if [ "${#secret}" -lt 32 ]; then
	echo "SUPABASE_JWT_SECRET is only ${#secret} chars. Use at least 32:" >&2
	echo "  openssl rand -base64 48 | tr -d '/+=' | head -c 64" >&2
	exit 1
fi

# base64URL, unpadded — RFC 7515. `-A` keeps it on one line; without it openssl
# wraps at 64 columns and the token silently contains newlines.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
# Ten years. This key is public and identifies the deployment rather than a
# person, so a short expiry buys nothing and would strand the installed app.
exp="$((now + 315360000))"

header="$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)"
payload="$(printf '{"role":"anon","iss":"supabase","iat":%s,"exp":%s}' "$now" "$exp" | b64url)"
signature="$(printf '%s.%s' "$header" "$payload" |
	openssl dgst -sha256 -hmac "$secret" -binary | b64url)"

printf '%s.%s.%s\n' "$header" "$payload" "$signature"
