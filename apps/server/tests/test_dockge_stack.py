"""The Dockge stack's SHAPE — what compose declares, not what the app reads.

`test_env_templates.py` owns the env-var inventory: every `Settings` field must
appear in every template. This file owns the other half, which drifted for different
reasons — the structure of `infra/dockge/compose.yaml` itself. Ports, networks, the
preflight gate, the image reference, and the self-hosted GoTrue's wiring are each a
decision that is correct-or-catastrophic and invisible in review once the file is
long enough.

Split out of `test_env_templates.py` when that file crossed 400 lines (standards §1).
Same idiom throughout: read the tracked file, assert the decision, and say in the
failure message what breaks when it is wrong.

⚠ Nothing here runs Docker. These prove what the repository ships.
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

# tests/test_dockge_stack.py → apps/server → apps → repo root.
_REPO_ROOT = Path(__file__).resolve().parents[3]
_DOCKGE_COMPOSE = _REPO_ROOT / "infra" / "dockge" / "compose.yaml"

# The services that run OUR image and read `Settings`. `db` is Postgres and `auth`
# is GoTrue; neither reads a line of our config.
_DOCKGE_APP_SERVICES = ("api", "preflight", "scheduler")


def _dockge_services() -> dict[str, dict]:
    """The Dockge stack's services, with YAML merge keys already resolved."""
    return yaml.safe_load(_DOCKGE_COMPOSE.read_text())["services"]


@pytest.mark.parametrize("service", _DOCKGE_APP_SERVICES)
def test_every_app_container_reads_the_whole_env_file(service: str) -> None:
    """`env_file: .env` is what makes the per-service listing — and its drift — go away.

    If someone replaces this with an explicit `environment:` list, the failure mode
    that cost us #56 is back: a var in the template that the process never sees.
    """
    declared = _dockge_services()[service].get("env_file")
    assert declared == ".env" or ".env" in (declared or []), (
        f"the dockge {service} service no longer reads the whole .env — if it has gone "
        f"back to an explicit environment: list, every Settings var must be in it"
    )


def test_the_preflight_validates_the_same_config_the_api_will_run() -> None:
    """⛔ The load-bearing invariant of the whole update mechanism.

    The preflight's job is to prove the NEW image can boot with THIS env before the
    working container is replaced. It can only prove that if it is handed the same
    environment. A preflight running on a subset would pass, the api would then fail
    its own validation, and the outcome is the exact failure the gate exists to
    prevent — except now it carries a green preflight's endorsement.
    """
    services = _dockge_services()
    api_env = {"env_file": services["api"].get("env_file")} | dict(
        services["api"].get("environment") or {}
    )
    pre_env = {"env_file": services["preflight"].get("env_file")} | dict(
        services["preflight"].get("environment") or {}
    )
    # The api additionally pins its bind address; the preflight serves nothing, so it
    # has no opinion on API_HOST/API_PORT and the .env values stand.
    assert pre_env == {k: v for k, v in api_env.items() if k not in {"API_HOST", "API_PORT"}}, (
        "the preflight and the api no longer receive the same configuration, so a "
        "green preflight stops meaning the api can boot"
    )


def test_the_api_is_gated_on_the_preflight_completing() -> None:
    """This dependency IS the update button's safety. Without it, `up -d` swaps the
    image with nothing having checked the schema or the config."""
    depends = _dockge_services()["api"]["depends_on"]
    assert "preflight" in depends, (
        "the api no longer depends on the preflight — Dockge's update button would "
        "deploy a schema-changing release straight over the running one"
    )
    assert depends["preflight"]["condition"] == "service_completed_successfully", (
        "the preflight's EXIT STATUS is the gate; any weaker condition ignores it"
    )


def test_the_preflight_only_checks_and_never_migrates() -> None:
    """It runs before the backup and before the stop. Applying here would move the
    schema under the still-running old containers with no dump taken."""
    command = _dockge_services()["preflight"]["command"]
    assert "--check" in command, f"the preflight command lost --check: {command}"


def test_the_api_binds_to_a_required_explicit_address() -> None:
    """⛔ The bind address is this deployment's security boundary.

    Traefik is on a DIFFERENT machine, so the port cannot be 127.0.0.1 any more — it
    has to be reachable across the private network. That removes the safety the old
    same-host setup got for free, and makes the address the only thing standing
    between the internet and an API whose sole protection is a bearer token: no TLS,
    no rate limit, nothing. Docker writes its iptables rules AHEAD of ufw, so a
    firewall rule does not save a 0.0.0.0 bind either.

    Required, with no default, because every plausible default is wrong: 0.0.0.0
    publishes it to the world and 127.0.0.1 makes it unroutable.
    """
    ports = _dockge_services()["api"]["ports"]
    assert len(ports) == 1, f"expected exactly one published port, got {ports}"
    assert ports[0].startswith("${HEALTHEE_BIND_ADDR:?"), (
        f"the api port is published as {ports[0]!r} — the bind address must be a "
        f"REQUIRED variable, so a deployment that forgot it refuses to start rather "
        f"than guessing 0.0.0.0"
    )
    assert ports[0].endswith(":8765:8765"), f"the published port moved: {ports[0]}"


def test_no_service_publishes_a_wildcard_or_loopback_port() -> None:
    """The two wrong answers, pinned so neither can be pasted back in."""
    for name, service in _dockge_services().items():
        for published in service.get("ports", []):
            assert not published.startswith(("0.0.0.0:", "127.0.0.1:", "8765:")), (
                f"{name} publishes {published!r}: a bare or wildcard bind exposes the "
                f"API to the internet with no TLS and no rate limit in front"
            )


@pytest.mark.parametrize("service", ["db", "scheduler", "preflight"])
def test_only_the_api_is_reachable_from_outside_the_stack(service: str) -> None:
    """The database, the job runner and the gate serve nothing and must not be
    routable. Only the api publishes a port; everything else talks over the internal
    compose network."""
    assert "ports" not in _dockge_services()[service], (
        f"{service} publishes a port — it has no HTTP surface, and on a box whose "
        f"private network another machine can reach, that is a real exposure"
    )


def test_the_image_reference_has_no_default_namespace() -> None:
    """⛔ An unset HEALTHEE_IMAGE must REFUSE, not guess.

    The only namespace a default could name is the upstream project's. An operator
    who never set it would then pull an image they did not build, from a repository
    they do not control, and the stack would come up green — which is worse than any
    error message. `${VAR:?...}` is compose's required-variable form.
    """
    image = _dockge_services()["api"]["image"]
    assert image.startswith("${HEALTHEE_IMAGE:?"), (
        f"the api image is {image!r} — it must be a REQUIRED variable, so that a "
        f"deployment which forgot to set it fails loudly instead of running "
        f"somebody else's build"
    )


def test_every_app_service_runs_the_same_image() -> None:
    """The preflight only proves anything about the image the api will actually run."""
    images = {service: _dockge_services()[service]["image"] for service in _DOCKGE_APP_SERVICES}
    assert len(set(images.values())) == 1, (
        f"the app services no longer share one image: {images} — a preflight that "
        f"checks a different build than the api runs endorses nothing"
    )


# ── The self-hosted GoTrue (infra/dockge, `auth` service) ───────────────────


def test_gotrue_and_the_api_are_given_the_same_signing_secret() -> None:
    """⛔ The invariant the whole self-hosted sign-in rests on.

    GoTrue SIGNS the access token; the API VERIFIES it. Those are two processes
    reading two environment variables, and if the values ever differ the failure is
    maximally confusing: sign-in SUCCEEDS at GoTrue, the app gets a token that looks
    real, and every `/api/*` call then 401s. That reads as "the server is broken",
    not as "two secrets disagree".

    Compose interpolates BOTH from the single `.env` key, so they cannot drift. This
    asserts the interpolation, because an `environment:` block is exactly the place
    someone later pastes a literal.
    """
    auth_env = _dockge_services()["auth"]["environment"]
    assert auth_env["GOTRUE_JWT_SECRET"].startswith("${SUPABASE_JWT_SECRET"), (
        f"GoTrue's signing secret is {auth_env['GOTRUE_JWT_SECRET']!r} — it must "
        f"interpolate the same .env key the api verifies with, not a literal"
    )
    # The api reads the whole .env, so it gets SUPABASE_JWT_SECRET from the same key.
    assert _dockge_services()["api"].get("env_file") == ".env"


def test_gotrue_requires_its_db_password_rather_than_defaulting() -> None:
    """A blank password in the URL would have GoTrue connect as `gotrue` with no
    credential, which fails at Postgres in a way that reads as a network problem."""
    url = _dockge_services()["auth"]["environment"]["GOTRUE_DB_DATABASE_URL"]
    assert "${GOTRUE_DB_PASSWORD:?" in url, "GOTRUE_DB_PASSWORD must be required"


def test_gotrue_stores_its_users_in_the_backed_up_database() -> None:
    """⛔ Accounts must live where pg_dump already looks.

    The `auth` schema sits in the SAME database as the health data, so one dump
    covers both. A separate database would produce a restore that brings back every
    measurement and no way to log in — every `app_user` row keys off a uuid this
    service owns, so losing the accounts orphans all of it.
    """
    env = _dockge_services()["auth"]["environment"]
    assert env["GOTRUE_DB_NAMESPACE"] == "auth"
    assert "@db:5432/${POSTGRES_DB}" in env["GOTRUE_DB_DATABASE_URL"], (
        "GoTrue points at a database other than the one the backup dumps — a "
        "restore would come back with data and no accounts"
    )
