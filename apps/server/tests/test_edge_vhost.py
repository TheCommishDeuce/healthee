"""The tracked nginx vhost is asserted, not assumed — `AUTH_AUDIT.md` E2 and E3.

`tests/test_env_templates.py` already establishes the idiom this file follows: config
that lives outside Python drifts silently, so the test reads the file. Nothing here
runs nginx; what is asserted is that the vhost in the repository still says the things
the audit changed it to say, so a future edit that removes them is a failing build
rather than a discovery.

⚠ **The honest limit, stated because the audit stated it (H3).** Certbot rewrites this
file IN PLACE on the box, adding the `:443` listener. The file that actually serves
traffic therefore exists only there and cannot be reviewed from here. What this file can
prove is what the repository ships; it cannot prove what the VPS is running, and no test
in this repo can. That is why the security headers live inside the `server` block
certbot copies, and why HSTS is deliberately NOT asserted: it belongs to the TLS
listener this file does not own.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

# tests/test_edge_vhost.py → apps/server → apps → repo root.
#
# The TEMPLATE, which is the only tracked form: the installed vhost is rendered
# from it by `infra/nginx/render-vhost.sh` with the operator's own `PUBLIC_HOST`,
# and after certbot the live file is certbot's anyway. Asserting the template is
# asserting the thing every deployment is actually built from.
_VHOST = Path(__file__).resolve().parents[3] / "infra" / "nginx" / "healtheeapi.conf.template"


@pytest.fixture(scope="module")
def vhost() -> str:
    assert _VHOST.exists(), f"the tracked vhost moved: {_VHOST}"
    return _VHOST.read_text()


def test_the_host_is_a_placeholder_not_somebody_s_domain() -> None:
    """No real hostname is tracked here — that is what the template is for.

    A rendered vhost committed by accident would put one operator's domain in
    everybody's clone, which is the thing `render-vhost.sh` exists to prevent.
    """
    text = _VHOST.read_text()
    assert "server_name ${PUBLIC_HOST};" in text, (
        "server_name is no longer the placeholder — a real host may have been "
        "committed over the template"
    )


# ── E2: the body limit matches what the API actually accepts ─────────────────


def test_the_body_limit_is_megabytes_not_hundreds_of_megabytes(vhost: str) -> None:
    """It was `600M`, for a Gadgetbridge multipart upload that does not exist.

    There is no `UploadFile` and no multipart handler anywhere in the server, so the
    limit was a carry-over from the previous implementation — and it applied to
    `/ingest/helio` (the hypnogram amplifier) and `/api/coach` equally.
    """
    found = re.search(r"client_max_body_size\s+(\d+)([KMG]);", vhost)
    assert found, "client_max_body_size is not set at all"
    size, unit = int(found.group(1)), found.group(2)
    assert unit == "M", f"the body limit is measured in {unit}, which is not megabytes"
    assert size <= 16, f"client_max_body_size is {size}M — larger than any body we accept"


def test_the_old_limit_is_not_still_in_force_anywhere(vhost: str) -> None:
    """The comment may (and does) RECORD what the limit used to be and why that reason
    was wrong — that is what stops the next person restoring it. What must not survive
    is the directive itself, on `/` or scoped into any `location`."""
    directives = re.findall(r"^\s*client_max_body_size\s+(\S+);", vhost, re.MULTILINE)
    assert directives, "client_max_body_size is not set at all"
    assert "600M" not in directives, f"the 600M limit is still in force: {directives}"


def test_there_is_still_no_multipart_route_to_justify_a_large_limit() -> None:
    """The premise of E2, re-measured rather than quoted from the audit."""
    src = Path(__file__).resolve().parents[1] / "src"
    offenders = [
        str(path)
        for path in src.rglob("*.py")
        if re.search(r"\bUploadFile\b|multipart", path.read_text())
    ]
    assert not offenders, f"a multipart upload path exists now: {offenders}"


# ── E3: something bounds an unauthenticated caller at the edge ──────────────


def test_a_request_rate_limit_exists_and_is_applied(vhost: str) -> None:
    """There was no `limit_req` and no `limit_conn` anywhere.

    The only unauthenticated routes are `/healthz` and `/readyz`, and both run a
    `SELECT 1` on a pool of at most 10 — so the exposure was pool exhaustion by anybody
    at all.
    """
    assert re.search(r"limit_req_zone\s+\$binary_remote_addr\s+zone=\w+:\d+m\s+rate=\d+r/s;", vhost)
    assert re.search(r"^\s*limit_req\s+zone=\w+\s+burst=\d+", vhost, re.MULTILINE)


def test_a_throttled_caller_is_told_429_and_not_503(vhost: str) -> None:
    """ "You are asking too fast" and "the service is down" are different answers, and a
    client acts on them differently. nginx's default here is 503."""
    assert re.search(r"limit_req_status\s+429;", vhost)


def test_a_connection_limit_exists(vhost: str) -> None:
    assert re.search(r"limit_conn_zone\s+\$binary_remote_addr", vhost)
    assert re.search(r"^\s*limit_conn\s+\w+\s+\d+;", vhost, re.MULTILINE)


@pytest.mark.parametrize(
    "header", ["X-Content-Type-Options nosniff", "X-Frame-Options", "Referrer-Policy"]
)
def test_the_security_headers_are_set_always(vhost: str, header: str) -> None:
    """`always`, so they are present on error responses too — which is where a missing
    nosniff actually bites."""
    found = re.search(rf"add_header\s+{re.escape(header)}[^;]*\balways;", vhost)
    assert found, f"{header} is not set with `always`"
