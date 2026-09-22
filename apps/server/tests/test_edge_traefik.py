"""The Traefik edge is asserted, not assumed — the sibling of `test_edge_vhost.py`.

That file exists because config living outside Python drifts silently. This one
exists for the same reason and one more: the edge is being MOVED. nginx's body cap,
rate limit, connection cap and security headers each have a test next door; ported
to Traefik labels they would have had none, and a protection that quietly fails to
survive a migration is indistinguishable from one that was never there.

So the tests below are deliberately paired with the nginx ones. Several assert that
the two edges AGREE — while both exist, tightening one and forgetting the other is
the realistic mistake, and it would leave the repo unable to say what the limit is.

⚠ **The honest limit, same as the vhost's.** Nothing here runs Traefik. These prove
what the repository ships. Two protections cannot be expressed as labels at all —
Cloudflare IP trust and access-log suppression — so no test in this repo can cover
them; they are a human checklist at `infra/traefik/CHECKLIST.md`, and that is a
weaker guarantee, stated rather than hidden.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

# tests/test_edge_traefik.py → apps/server → apps → repo root.
_REPO_ROOT = Path(__file__).resolve().parents[3]
_COMPOSE = _REPO_ROOT / "infra" / "dockge" / "compose.yaml"
_VHOST = _REPO_ROOT / "infra" / "nginx" / "healtheeapi.conf.template"


@pytest.fixture(scope="module")
def labels() -> dict[str, str]:
    """The api service's Traefik labels, as a key→value mapping."""
    assert _COMPOSE.exists(), f"the dockge stack moved: {_COMPOSE}"
    raw = yaml.safe_load(_COMPOSE.read_text())["services"]["api"]["labels"]
    pairs = [label.split("=", 1) for label in raw]
    return {key: value for key, value in pairs}


@pytest.fixture(scope="module")
def vhost() -> str:
    return _VHOST.read_text()


def test_routing_is_enabled_and_points_at_the_app_port(labels: dict[str, str]) -> None:
    assert labels["traefik.enable"] == "true"
    assert labels["traefik.http.services.healthee.loadbalancer.server.port"] == "8765"


def test_the_host_is_a_placeholder_not_somebody_s_domain(labels: dict[str, str]) -> None:
    """Nothing tracked here names a real host — a clone carries nobody's server."""
    rule = labels["traefik.http.routers.healthee.rule"]
    assert rule == "Host(`${PUBLIC_HOST}`)", (
        f"the router rule is {rule!r} — a real hostname may have been committed over "
        f"the interpolation"
    )


def test_traefik_is_told_which_network_to_dial(labels: dict[str, str]) -> None:
    """The api is on TWO networks (healthee-net and the proxy). Without this label
    Traefik may resolve the container on healthee-net, which it is not attached to,
    and every request 502s with nothing in the app's log to explain it."""
    assert "traefik.docker.network" in labels


# ── The middlewares must be ATTACHED, not merely defined ────────────────────
#
# This is Traefik's own version of the `limit_req_zone` / `limit_req` distinction
# the nginx tests draw: a middleware that is declared and never referenced by the
# router is inert, and it looks exactly like a working one in the config file.


@pytest.mark.parametrize(
    "middleware", ["healthee-ratelimit", "healthee-inflight", "healthee-body", "healthee-headers"]
)
def test_each_middleware_is_both_defined_and_referenced(
    labels: dict[str, str], middleware: str
) -> None:
    defined = any(key.startswith(f"traefik.http.middlewares.{middleware}.") for key in labels)
    assert defined, f"{middleware} is referenced by the router but never defined"

    attached = labels["traefik.http.routers.healthee.middlewares"]
    assert middleware in attached, (
        f"{middleware} is defined but NOT in the router's middleware chain, so it is "
        f"inert — the protection reads as present and does nothing"
    )


# ── Parity with the edge being retired ──────────────────────────────────────


def test_the_body_cap_matches_the_vhost_it_replaces(labels: dict[str, str], vhost: str) -> None:
    """8 MB in both places, or the repo cannot say what the limit is.

    The largest body the API accepts is bounded by the models: 4,000 samples a page
    and GpsTrackIn's 28,800 points. There is no multipart route.
    """
    cap = "traefik.http.middlewares.healthee-body.buffering.maxrequestbodybytes"
    traefik_bytes = int(labels[cap])

    found = re.search(r"client_max_body_size\s+(\d+)M;", vhost)
    assert found, "the vhost's body limit is no longer expressed in megabytes"
    nginx_bytes = int(found.group(1)) * 1024 * 1024

    assert traefik_bytes == nginx_bytes, (
        f"Traefik caps bodies at {traefik_bytes} and nginx at {nginx_bytes}. While both "
        f"edges exist they must agree, or the limit depends on which one is in front."
    )
    assert traefik_bytes <= 16 * 1024 * 1024, "larger than any body we accept"


def test_the_rate_limit_matches_the_vhost_it_replaces(labels: dict[str, str], vhost: str) -> None:
    """20 r/s, burst 100 — from what the CLIENT does, not from a feeling.

    A full sync drain is at most maxPages 20 x maxDrainRounds 12 sequential POSTs;
    a screen load is a handful of GETs.
    """
    prefix = "traefik.http.middlewares.healthee-ratelimit.ratelimit"
    assert labels[f"{prefix}.period"] == "1s", "the average is per-second or the numbers below lie"
    average = int(labels[f"{prefix}.average"])
    burst = int(labels[f"{prefix}.burst"])

    nginx_rate = re.search(r"rate=(\d+)r/s;", vhost)
    nginx_burst = re.search(r"limit_req\s+zone=\w+\s+burst=(\d+)", vhost)
    assert nginx_rate and nginx_burst
    assert average == int(nginx_rate.group(1)), "the two edges disagree about the rate"
    assert burst == int(nginx_burst.group(1)), "the two edges disagree about the burst"


def test_the_connection_cap_matches_the_vhost_it_replaces(
    labels: dict[str, str], vhost: str
) -> None:
    amount = int(labels["traefik.http.middlewares.healthee-inflight.inflightreq.amount"])
    nginx_conn = re.search(r"^\s*limit_conn\s+\w+\s+(\d+);", vhost, re.MULTILINE)
    assert nginx_conn
    assert amount == int(nginx_conn.group(1)), "the two edges disagree about concurrency"


def test_the_rate_limiter_counts_a_configurable_client_ip(labels: dict[str, str]) -> None:
    """Behind Cloudflare, counting the TCP peer means the whole world shares one
    bucket and one owner's sync throttles everybody. The depth has to be settable,
    and both limiters must agree on it — two different answers to "who is the
    client" is worse than either answer alone."""
    rate_depth = labels[
        "traefik.http.middlewares.healthee-ratelimit.ratelimit.sourcecriterion.ipstrategy.depth"
    ]
    inflight_depth = labels[
        "traefik.http.middlewares.healthee-inflight.inflightreq.sourcecriterion.ipstrategy.depth"
    ]
    assert rate_depth == inflight_depth
    assert rate_depth.startswith("${"), (
        "the IP depth is hard-coded; it depends on whether the deployment is behind "
        "Cloudflare and must come from .env"
    )


@pytest.mark.parametrize(
    "header",
    [
        "traefik.http.middlewares.healthee-headers.headers.contenttypenosniff",
        "traefik.http.middlewares.healthee-headers.headers.framedeny",
        "traefik.http.middlewares.healthee-headers.headers.referrerpolicy",
    ],
)
def test_the_security_headers_survived_the_move(labels: dict[str, str], header: str) -> None:
    """Each of these has a test against the nginx vhost next door. Losing one in the
    port would be a silent regression with a green deploy."""
    assert header in labels, f"{header.rsplit('.', 1)[-1]} is not set on the Traefik edge"


def test_hsts_is_asserted_here_because_traefik_owns_tls(labels: dict[str, str]) -> None:
    """The nginx template deliberately does NOT set HSTS: it owned only the :80
    vhost, and asserting it there would have been a promise that file could not
    keep. Traefik terminates TLS, so here it is ours to make."""
    seconds = int(labels["traefik.http.middlewares.healthee-headers.headers.stsseconds"])
    assert seconds >= 31536000, "HSTS is set to less than a year, which browsers treat as weak"
