"""The env templates and the compose file must stay a complete inventory of `Settings`.

This is the cheap check that would have prevented #56. Every field on
`core.config.Settings` defaults to something constructible, so a var missing from the
file a deployer copies produces an API that **starts, reports `/healthz` green, and
runs a dead subsystem**. Nothing in the deploy can see that: the templates are prose,
compose is YAML, and `Settings` is Python, so the three drift apart silently and the
only detector was someone noticing a 400 in a log.

Three invariants, each catching a different half of the drift:

1. **`infra/.env.example` declares every field, uncommented.** It is the file an
   operator copies to `infra/.env`; a commented line there is a var they will not set.
2. **`apps/server/.env.example` declares every field**, commented allowed — it is the
   local-dev inventory, and a var like `API_HOST` is documented rather than required.
3. **The compose `api` service passes every field through.** `LLM_TIMEOUT_S` and
   `LLM_MAX_RETRIES` were in `infra/.env.example` and *not* in compose, so setting
   them in prod's `.env` did nothing at all — a template promising something the
   container never received, which is #56's exact shape one layer down.

Plus the reverse direction: a key in a template that `Settings` does not read is
either a typo (`DEFAULT_MODLE=`) or a var nobody consumes. Both are caught by pinning
the deploy-only names explicitly.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

from healthee.core.config import Settings

# tests/test_env_templates.py → apps/server → apps → repo root.
_REPO_ROOT = Path(__file__).resolve().parents[3]
_INFRA_TEMPLATE = _REPO_ROOT / "infra" / ".env.example"
_DEV_TEMPLATE = _REPO_ROOT / "apps" / "server" / ".env.example"
_COMPOSE = _REPO_ROOT / "infra" / "docker" / "docker-compose.prod.yml"
_DOCKGE_COMPOSE = _REPO_ROOT / "infra" / "dockge" / "compose.yaml"
_DOCKGE_TEMPLATE = _REPO_ROOT / "infra" / "dockge" / ".env.example"

# The services in the Dockge stack that run OUR image and read `Settings`. `db` is
# Postgres and reads none of it.
_DOCKGE_APP_SERVICES = ("api", "preflight", "scheduler")

# Vars in `infra/.env.example` that `Settings` deliberately does NOT read: they are
# consumed by the shell (deploy.sh, backup/pg_dump_backup.sh), never by the app. Named
# one by one rather than pattern-matched, so a typo'd app var cannot hide among them.
_DEPLOY_ONLY_VARS = frozenset(
    {
        "DEPLOY_BRANCH",  # infra/deploy.sh — the branch the VPS resets to
        "BACKUP_DIR",  # infra/backup/pg_dump_backup.sh — where dumps are written
        "BACKUP_RETENTION_DAYS",  # …and how long they are kept
        "OFFBOX_CMD",  # …and the optional off-box copy command
        # infra/nginx/render-vhost.sh — the public DNS name, substituted into the
        # vhost's `server_name`. Deploy-only on purpose: the app is behind nginx and
        # never needs to know what it is reached as, so `Settings` reading this would
        # be a second source of truth for a question the app cannot answer better
        # than the proxy in front of it. NOT `API_HOST`, which is the bind address
        # inside the container and IS read.
        "PUBLIC_HOST",
    }
)

# Vars only the DOCKGE stack declares: they are consumed by compose interpolation
# (the image tag, the Traefik labels), never by the app. Kept separate from
# `_DEPLOY_ONLY_VARS` so `infra/.env.example` cannot quietly grow Traefik settings
# that the nginx deployment would never act on.
_DOCKGE_ONLY_VARS = frozenset(
    {
        "HEALTHEE_IMAGE",  # which repository the image is pulled from
        "HEALTHEE_IMAGE_TAG",  # which published image the stack runs
        "HEALTHEE_BUILD_LOCALLY",  # build on the box instead of pulling
        "TRAEFIK_NETWORK",  # the external proxy network to join and be dialled on
        "TRAEFIK_ENTRYPOINT",
        "TRAEFIK_CERTRESOLVER",
        "TRAEFIK_IP_DEPTH",  # which IP the rate limiter counts against
    }
)

# Vars the DEV template may declare and the infra one may not: they belong to tooling that
# runs on a developer's machine and must never reach the VPS (`infra/DEPLOY.md` §E2).
_DEV_ONLY_VARS = frozenset(
    {
        "EVAL_OPENROUTER_API_KEY",  # tests/grounding_eval — a paid arm's own small-limit key
    }
)

_ASSIGNMENT = re.compile(r"^(?P<commented>#\s*)?(?P<name>[A-Z][A-Z0-9_]*)\s*=")


def _settings_vars() -> set[str]:
    """Every env var name `Settings` reads, as the templates spell it."""
    return {name.upper() for name in Settings.model_fields}


def _declared(template: Path, *, include_commented: bool) -> set[str]:
    """Var names assigned in `template`, optionally counting commented-out lines."""
    found: set[str] = set()
    for line in template.read_text().splitlines():
        match = _ASSIGNMENT.match(line)
        if match and (include_commented or not match["commented"]):
            found.add(match["name"])
    return found


def _compose_env(service: str) -> set[str]:
    """The env var names a compose service passes into its container."""
    services = yaml.safe_load(_COMPOSE.read_text())["services"]
    return set(services[service]["environment"])


def test_the_infra_template_declares_every_setting_uncommented() -> None:
    """`infra/.env.example` is the file a deployer copies — nothing may be missing.

    Uncommented specifically: a commented var is documentation, and an operator who
    copies this file will not set it. That is how `SUPABASE_JWT_SECRET` could be
    absent on a box whose API was green.
    """
    missing = _settings_vars() - _declared(_INFRA_TEMPLATE, include_commented=False)
    assert not missing, (
        f"infra/.env.example does not declare {sorted(missing)} — a deployer copying "
        f"it gets an app that starts with those silently blank"
    )


def test_the_dev_template_declares_every_setting() -> None:
    """`apps/server/.env.example` is the local-dev inventory; commented counts here.

    A dev never needs `API_HOST`, but the template still has to *name* it, or the next
    person adding a setting has no file that lists what exists.
    """
    missing = _settings_vars() - _declared(_DEV_TEMPLATE, include_commented=True)
    assert not missing, f"apps/server/.env.example does not mention {sorted(missing)}"


def test_the_templates_declare_nothing_the_app_does_not_read() -> None:
    """The reverse direction: an unknown key is a typo or a var nobody consumes."""
    base = _settings_vars() | _DEPLOY_ONLY_VARS
    for template, allowed in ((_INFRA_TEMPLATE, base), (_DEV_TEMPLATE, base | _DEV_ONLY_VARS)):
        unknown = _declared(template, include_commented=True) - allowed
        assert not unknown, (
            f"{template.name} declares {sorted(unknown)}, which `Settings` does not "
            f"read and is not a known deploy-only var — a typo'd name is silently inert"
        )


def test_the_eval_key_is_offered_to_developers_and_withheld_from_the_vps() -> None:
    """`EVAL_OPENROUTER_API_KEY` belongs on a dev machine and nowhere near production.

    Both halves matter. Naming it in the dev template is how anyone learns the variable
    exists at all; keeping it out of `infra/.env.example` is `DEPLOY.md` §E2's actual
    rule — an eval key that reaches the VPS is just the production key again, and #102
    was two keys' worth of traffic on one balance.
    """
    assert "EVAL_OPENROUTER_API_KEY" in _declared(_DEV_TEMPLATE, include_commented=True), (
        "apps/server/.env.example never mentions EVAL_OPENROUTER_API_KEY, so the "
        "separate-key setup is documented only where nobody copies from"
    )
    assert "EVAL_OPENROUTER_API_KEY" not in _declared(_INFRA_TEMPLATE, include_commented=True), (
        "infra/.env.example is copied onto the VPS — an eval key must never be deployed"
    )


def test_the_api_container_receives_every_setting() -> None:
    """Compose must forward every var, or the template is promising the operator air.

    `LLM_TIMEOUT_S`/`LLM_MAX_RETRIES` lived in `infra/.env.example` while compose never
    passed them, so a bound the file documented in detail was simply not in effect.
    """
    missing = _settings_vars() - _compose_env("api")
    assert not missing, (
        f"docker-compose.prod.yml's api service does not pass {sorted(missing)} — "
        f"setting them in infra/.env would have no effect on the container"
    )


@pytest.mark.parametrize("var", ["OPENROUTER_API_KEY", "DEFAULT_MODEL", "COACH_MODEL"])
def test_the_scheduler_receives_the_llm_config(var: str) -> None:
    """The scheduler IS the nightly chain, so its LLM config is not optional.

    It is not checked for the full set (it verifies no JWTs and binds no port), but a
    missing model id or bound here breaks the surface that runs unattended.
    """
    assert var in _compose_env("scheduler"), f"the scheduler container never receives {var}"


def test_the_llm_bounds_reach_the_scheduler() -> None:
    """The single-threaded tick loop is where an unbounded call costs the most."""
    scheduler = _compose_env("scheduler")
    assert {"LLM_TIMEOUT_S", "LLM_MAX_RETRIES"} <= scheduler, (
        "the scheduler runs the nightly chain on one thread — without these it "
        "inherits the SDK's 600 s × 3, and one stuck call blocks every later owner"
    )


def test_the_scheduler_receives_the_self_host_unlock() -> None:
    """The nightly chain decides entitlement too (§12.3), so the flag must reach it.

    Without it a SELF-HOSTED install would serve its owner the AI layer over HTTP while
    the scheduler — a separate container, reading its own environment — treated them as
    free and silently generated nothing: recs, briefing and the daily action all absent,
    with a green API and no error anywhere. That is a whole-feature outage that looks
    like "the AI just isn't very good".
    """
    assert "SELF_HOST_UNLOCKED" in _compose_env("scheduler"), (
        "the scheduler container never receives SELF_HOST_UNLOCKED — a self-hosted "
        "install's nightly chain would skip every AI step for every owner"
    )


# ── The Dockge stack (infra/dockge/) ────────────────────────────────────────
#
# Same drift problem, a different shape of answer. The prod compose lists every var
# per service, which is what let `LLM_TIMEOUT_S` be documented, set, and never
# received. The Dockge stack passes the whole `.env` through with `env_file:`, so
# that particular drift is impossible by construction — and these tests hold the
# construction in place rather than re-checking the list it replaced.


def _dockge_services() -> dict[str, dict]:
    """The Dockge stack's services, with YAML merge keys already resolved."""
    return yaml.safe_load(_DOCKGE_COMPOSE.read_text())["services"]


def test_the_dockge_template_declares_every_setting_uncommented() -> None:
    """It is the file Dockge shows an operator and writes back — nothing may be missing."""
    missing = _settings_vars() - _declared(_DOCKGE_TEMPLATE, include_commented=False)
    assert not missing, (
        f"infra/dockge/.env.example does not declare {sorted(missing)} — and because "
        f"compose passes this file through wholesale, a var absent here is a var the "
        f"container never receives"
    )


def test_the_dockge_template_declares_nothing_the_app_does_not_read() -> None:
    """An unknown key is a typo or a var nobody consumes; both are silently inert."""
    allowed = _settings_vars() | _DEPLOY_ONLY_VARS | _DOCKGE_ONLY_VARS
    unknown = _declared(_DOCKGE_TEMPLATE, include_commented=True) - allowed
    assert not unknown, f"infra/dockge/.env.example declares {sorted(unknown)}, which nothing reads"


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


def test_the_api_publishes_no_port_to_the_host() -> None:
    """Traefik reaches the container on the proxy network. A published port is a
    second, unprotected way in that bypasses every middleware on the router —
    the rate limit, the body cap and the security headers all live there."""
    assert "ports" not in _dockge_services()["api"], (
        "the dockge api service publishes a port; Traefik does not need one and "
        "anything bound on the host skips the middleware chain entirely"
    )


@pytest.mark.parametrize("service", ["db", "scheduler"])
def test_only_the_api_is_on_the_proxy_network(service: str) -> None:
    """The database and the job runner serve nothing and must not be routable."""
    assert "proxy" not in _dockge_services()[service].get("networks", []), (
        f"{service} is on the Traefik network — it has no HTTP surface and nothing "
        f"outside this stack should be able to reach it"
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
