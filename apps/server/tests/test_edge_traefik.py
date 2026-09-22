"""The Traefik edge is asserted, not assumed — the sibling of `test_edge_vhost.py`.

That file exists because config living outside Python drifts silently. This one
exists for the same reason and one more: the edge is being MOVED. nginx's body cap,
rate limit, connection cap and security headers each have a test next door; ported
to Traefik they would have had none, and a protection that quietly fails to survive
a migration is indistinguishable from one that was never there.

So the tests below are deliberately paired with the nginx ones. Several assert that
the two edges AGREE — while both exist, tightening one and forgetting the other is
the realistic mistake, and it would leave the repo unable to say what the limit is.

⚠ **Traefik runs on a DIFFERENT HOST from the app.** That is why this reads a config
file rather than container labels: Traefik's Docker provider reads labels from its
own daemon's socket and cannot see another machine's containers. Labels would have
been inert, the stack would have come up green, and nothing would have been routed.
The tracked form is therefore `infra/traefik/healthee.yml.template`, rendered per
deployment by `render-dynamic.sh` — asserting the template is asserting what every
deployment is built from.

⚠ **The honest limit, same as the vhost's.** Nothing here runs Traefik. These prove
what the repository ships, not what your Traefik host is running. Two protections
cannot live in this file at all — Cloudflare IP trust and access-log suppression are
Traefik's *static* config — so no test here can cover them; they are a human
checklist at `infra/traefik/CHECKLIST.md`, which is a weaker guarantee, stated
rather than hidden.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import pytest
import yaml

# tests/test_edge_traefik.py → apps/server → apps → repo root.
_REPO_ROOT = Path(__file__).resolve().parents[3]
_TEMPLATE = _REPO_ROOT / "infra" / "traefik" / "healthee.yml.template"
_RENDER = _REPO_ROOT / "infra" / "traefik" / "render-dynamic.sh"
_COMPOSE = _REPO_ROOT / "infra" / "dockge" / "compose.yaml"
_VHOST = _REPO_ROOT / "infra" / "nginx" / "healtheeapi.conf.template"


@pytest.fixture(scope="module")
def dynamic() -> dict[str, Any]:
    """The tracked Traefik dynamic config. Placeholders survive YAML parsing."""
    assert _TEMPLATE.exists(), f"the tracked Traefik config moved: {_TEMPLATE}"
    return yaml.safe_load(_TEMPLATE.read_text())["http"]


@pytest.fixture(scope="module")
def middlewares(dynamic: dict[str, Any]) -> dict[str, Any]:
    return dynamic["middlewares"]


@pytest.fixture(scope="module")
def vhost() -> str:
    return _VHOST.read_text()


# ── The split-host topology itself ──────────────────────────────────────────


def test_the_stack_carries_no_traefik_labels() -> None:
    """⛔ Labels are inert here, and inert config that LOOKS live is the trap.

    Traefik's Docker provider reads its own daemon's socket. Ours is on another
    machine, so a `traefik.*` label on these containers is never read by anything —
    the stack comes up healthy and the site is simply never routed. Anyone
    reintroducing labels is reverting to a setup that cannot work in this topology.
    """
    offenders = [
        line.strip()
        for line in _COMPOSE.read_text().splitlines()
        if re.match(r'\s*-\s*"?traefik\.', line)
    ]
    assert not offenders, (
        f"the Dockge stack has traefik.* labels again: {offenders}. Traefik runs on a "
        f"different host and will never read them; the routing lives in "
        f"infra/traefik/healthee.yml.template."
    )


def test_the_host_is_a_placeholder_not_somebody_s_domain(dynamic: dict[str, Any]) -> None:
    """Nothing tracked here names a real host — a clone carries nobody's server."""
    rule = dynamic["routers"]["healthee"]["rule"]
    assert rule == "Host(`${PUBLIC_HOST}`)", (
        f"the router rule is {rule!r} — a real hostname may have been committed over "
        f"the placeholder"
    )


def test_the_backend_is_a_placeholder_not_somebody_s_private_ip(
    dynamic: dict[str, Any],
) -> None:
    """Same reason, and a private IP is the easier one to paste in by accident."""
    servers = dynamic["services"]["healthee"]["loadBalancer"]["servers"]
    assert [s["url"] for s in servers] == ["http://${HEALTHEE_BIND_ADDR}:8765"]


def test_the_renderer_refuses_a_loopback_backend() -> None:
    """⛔ The mistake this topology invites, caught at render rather than at 502.

    `127.0.0.1` is what the same-host nginx setup used and what a half-copied runbook
    leaves behind. On the Traefik host it means Traefik itself, so it would proxy to
    its own port 8765 and serve a connection refused that names nothing.
    """
    script = _RENDER.read_text()
    assert "127.*" in script, "render-dynamic.sh no longer rejects a loopback backend"
    assert "0.0.0.0" in script, "render-dynamic.sh no longer rejects a wildcard backend"


def test_traefik_health_checks_the_backend_over_the_private_network(
    dynamic: dict[str, Any],
) -> None:
    """Cross-host, the link can fail independently of both machines.

    Without an active health check Traefik keeps routing to a box it cannot reach and
    every request waits out a dial timeout; with one the router fails fast and says
    which server is down. This matters here in a way it did not when the proxy and
    the app shared a kernel.
    """
    check = dynamic["services"]["healthee"]["loadBalancer"]["healthCheck"]
    assert check["path"] == "/healthz", "the health check must use the unauthenticated route"


# ── The middlewares must be ATTACHED, not merely defined ────────────────────


@pytest.mark.parametrize(
    "middleware", ["healthee-ratelimit", "healthee-inflight", "healthee-body", "healthee-headers"]
)
def test_each_middleware_is_both_defined_and_referenced(
    dynamic: dict[str, Any], middleware: str
) -> None:
    """A middleware defined and never referenced is inert, and in a config file it
    looks exactly like a working one. This is Traefik's version of the
    `limit_req_zone` / `limit_req` distinction the nginx tests draw."""
    assert middleware in dynamic["middlewares"], f"{middleware} is referenced but never defined"
    assert middleware in dynamic["routers"]["healthee"]["middlewares"], (
        f"{middleware} is defined but NOT in the router's chain, so it is inert — the "
        f"protection reads as present and does nothing"
    )


def test_the_rate_limit_is_applied_before_the_body_is_buffered(
    dynamic: dict[str, Any],
) -> None:
    """Order matters, and cross-host it matters more.

    Traefik buffers the 8 MB body on the TRAEFIK host's disk. Rate-limiting after
    buffering would let a flood spend that disk before being refused — on the machine
    that also fronts everything else you run.
    """
    chain = dynamic["routers"]["healthee"]["middlewares"]
    assert chain.index("healthee-ratelimit") < chain.index("healthee-body"), (
        f"the chain is {chain} — reject cheaply first, or a flood is spooled to disk "
        f"before it is refused"
    )


# ── Parity with the edge being retired ──────────────────────────────────────


def test_the_body_cap_matches_the_vhost_it_replaces(
    middlewares: dict[str, Any], vhost: str
) -> None:
    """8 MB in both places, or the repo cannot say what the limit is."""
    traefik_bytes = int(middlewares["healthee-body"]["buffering"]["maxRequestBodyBytes"])

    found = re.search(r"client_max_body_size\s+(\d+)M;", vhost)
    assert found, "the vhost's body limit is no longer expressed in megabytes"
    nginx_bytes = int(found.group(1)) * 1024 * 1024

    assert traefik_bytes == nginx_bytes, (
        f"Traefik caps bodies at {traefik_bytes} and nginx at {nginx_bytes}. While both "
        f"edges exist they must agree, or the limit depends on which one is in front."
    )
    assert traefik_bytes <= 16 * 1024 * 1024, "larger than any body we accept"


def test_the_rate_limit_matches_the_vhost_it_replaces(
    middlewares: dict[str, Any], vhost: str
) -> None:
    """20 r/s, burst 100 — from what the CLIENT does, not from a feeling."""
    limit = middlewares["healthee-ratelimit"]["rateLimit"]
    assert str(limit["period"]) in {"1s", "1"}, "the average is per-second or the numbers lie"

    nginx_rate = re.search(r"rate=(\d+)r/s;", vhost)
    nginx_burst = re.search(r"limit_req\s+zone=\w+\s+burst=(\d+)", vhost)
    assert nginx_rate and nginx_burst
    assert int(limit["average"]) == int(nginx_rate.group(1)), "the edges disagree on the rate"
    assert int(limit["burst"]) == int(nginx_burst.group(1)), "the edges disagree on the burst"


def test_the_connection_cap_matches_the_vhost_it_replaces(
    middlewares: dict[str, Any], vhost: str
) -> None:
    amount = int(middlewares["healthee-inflight"]["inFlightReq"]["amount"])
    nginx_conn = re.search(r"^\s*limit_conn\s+\w+\s+(\d+);", vhost, re.MULTILINE)
    assert nginx_conn
    assert amount == int(nginx_conn.group(1)), "the two edges disagree about concurrency"


def test_both_limiters_agree_on_who_the_client_is(middlewares: dict[str, Any]) -> None:
    """Behind Cloudflare, counting the TCP peer means the whole world shares one
    bucket. The depth must be settable, and two different answers to "who is the
    client" would be worse than either answer alone."""
    rate = middlewares["healthee-ratelimit"]["rateLimit"]["sourceCriterion"]["ipStrategy"]
    inflight = middlewares["healthee-inflight"]["inFlightReq"]["sourceCriterion"]["ipStrategy"]
    assert rate["depth"] == inflight["depth"]
    assert str(rate["depth"]).startswith("${"), (
        "the IP depth is hard-coded; it depends on whether the deployment is behind "
        "Cloudflare and must be rendered from .env"
    )


@pytest.mark.parametrize(
    "header,expected",
    [("contentTypeNosniff", True), ("frameDeny", True), ("referrerPolicy", "no-referrer")],
)
def test_the_security_headers_survived_the_move(
    middlewares: dict[str, Any], header: str, expected: object
) -> None:
    """Each has a test against the nginx vhost next door. Losing one in the port
    would be a silent regression with a green deploy."""
    assert middlewares["healthee-headers"]["headers"][header] == expected


def test_hsts_is_asserted_here_because_traefik_owns_tls(middlewares: dict[str, Any]) -> None:
    """The nginx template deliberately does NOT set HSTS: it owned only the :80
    vhost, and asserting it there would be a promise that file could not keep.
    Traefik terminates TLS, so here it is ours to make."""
    seconds = int(middlewares["healthee-headers"]["headers"]["stsSeconds"])
    assert seconds >= 31536000, "HSTS is under a year, which browsers treat as weak"
