"""QR enrollment end to end — docs/QR_ENROLLMENT.md's properties, one per test.

Written against what each property protects rather than the call that implements it:
a code must enroll exactly once, a phone token must read AND write for its own owner
only, an ingest token must still not read, a phone must not mint credentials, and a
revoked phone must stop on both paths.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import jwt
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from healthee.api.routers import auth
from healthee.core.config import get_settings
from healthee.core.db import admin_connection, transaction
from healthee.core.device_token import (
    _MAX_LIVE_DEVICE_TOKENS,
    PHONE_TOKEN_PREFIX,
    mint_device_token,
    revoke_device_token,
)
from healthee.core.enrollment import issue_enrollment_code, redeem_enrollment_code
from healthee.core.request_auth import IngestUser
from healthee.db import enroll, migrate

pytestmark = [pytest.mark.integration, pytest.mark.usefixtures("owner_sweep")]

_SECRET = "enrollment-integration-secret-0123456789abcdef"
_INGEST = "/ingest-guarded"


@pytest.fixture
def configured(db: None, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:  # noqa: ARG001
    monkeypatch.setenv("SUPABASE_JWT_SECRET", _SECRET)
    monkeypatch.setenv("SUPABASE_JWT_AUD", "authenticated")
    monkeypatch.delenv("SUPABASE_PROJECT_REF", raising=False)
    get_settings.cache_clear()
    migrate.apply_migrations()
    yield
    get_settings.cache_clear()


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(auth.router)

    @app.get(_INGEST)
    def _ingest(user: IngestUser) -> dict[str, str]:
        return {"id": str(user.id)}

    return TestClient(app)


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _jwt(sub: UUID) -> str:
    payload: dict[str, Any] = {
        "sub": str(sub),
        "aud": "authenticated",
        "exp": datetime.now(tz=UTC) + timedelta(hours=1),
    }
    return jwt.encode(payload, _SECRET, algorithm="HS256")


def _seed_owner(email: str | None = None) -> UUID:
    uid = uuid4()
    with transaction() as cur:
        cur.execute("INSERT INTO app_user (id, email) VALUES (%s, %s)", (str(uid), email))
    return uid


def _issue(uid: UUID, label: str | None = "Pixel", ttl: timedelta | None = None) -> str:
    with admin_connection() as conn, conn.cursor() as cur:
        if ttl is None:
            return issue_enrollment_code(cur, uid, label)
        return issue_enrollment_code(cur, uid, label, ttl)


def test_a_code_enrolls_a_phone_that_reads_and_writes_as_its_owner(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    code = _issue(uid)

    resp = _client().post("/api/enroll", json={"code": code, "label": "Owner's phone"})

    assert resp.status_code == 200, resp.text
    body = resp.json()
    token = body["device_token"]
    assert token.startswith(PHONE_TOKEN_PREFIX)
    assert body["user_id"] == str(uid)
    assert _client().get("/api/me", headers=_bearer(token)).json()["id"] == str(uid)
    assert _client().get(_INGEST, headers=_bearer(token)).json()["id"] == str(uid)
    with transaction() as cur:
        cur.execute(
            "SELECT t.scope, t.label, c.used_at IS NOT NULL FROM enrollment_code c "
            "JOIN device_token t ON t.id = c.device_token_id WHERE c.user_id = %s",
            (str(uid),),
        )
        assert cur.fetchall() == [("phone", "Owner's phone", True)]


def test_a_code_enrolls_exactly_once(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    code = _issue(uid)

    assert redeem_enrollment_code(code, None) is not None
    assert redeem_enrollment_code(code, None) is None


def test_unknown_used_and_expired_codes_get_the_same_answer(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    used = _issue(uid)
    assert redeem_enrollment_code(used, None) is not None
    expired = _issue(uid)
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE enrollment_code SET expires_at = now() - interval '1 second' "
            "WHERE user_id = %s AND used_at IS NULL",
            (str(uid),),
        )

    answers = {
        name: _client().post("/api/enroll", json={"code": code})
        for name, code in (("unknown", "no-such-code"), ("used", used), ("expired", expired))
    }

    assert {name: r.status_code for name, r in answers.items()} == dict.fromkeys(answers, 401)
    assert len({r.json()["detail"] for r in answers.values()}) == 1


def test_the_code_label_names_the_token_when_the_phone_sends_none(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    enrolled = redeem_enrollment_code(_issue(uid, label="Spare phone"), None)
    assert enrolled is not None
    with transaction() as cur:
        cur.execute("SELECT label FROM device_token WHERE id = %s", (str(enrolled.token_id),))
        assert cur.fetchone() == ("Spare phone",)


def test_an_ingest_token_still_cannot_read(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    raw, _ = mint_device_token(uid, label=None)

    assert _client().get("/api/me", headers=_bearer(raw)).status_code == 401
    # Even dressed up with the phone prefix it is not a phone token.
    forged = _client().get("/api/me", headers=_bearer(PHONE_TOKEN_PREFIX + raw))
    assert forged.status_code == 401


def test_an_ingest_token_that_happens_to_carry_the_prefix_still_cannot_read(
    configured: None,  # noqa: ARG001
) -> None:
    """The prefix routes; the SCOPE authorises. A random ingest token starts with
    `hph_` about once in 17 million mints, and that one must not become a reader."""
    uid = _seed_owner()
    raw = PHONE_TOKEN_PREFIX + "an-ingest-token-that-drew-the-prefix"
    with transaction() as cur:
        cur.execute(
            "INSERT INTO device_token (user_id, token_hash, scope) VALUES (%s, %s, 'ingest')",
            (str(uid), hashlib.sha256(raw.encode()).hexdigest()),
        )

    assert _client().get(_INGEST, headers=_bearer(raw)).json()["id"] == str(uid)
    assert _client().get("/api/me", headers=_bearer(raw)).status_code == 401


def test_a_phone_cannot_mint_or_list_credentials(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    enrolled = redeem_enrollment_code(_issue(uid), None)
    assert enrolled is not None
    headers = _bearer(enrolled.token)

    assert _client().post("/api/device", headers=headers, json={}).status_code == 401
    assert _client().get("/api/device", headers=headers).status_code == 401
    # The same owner signed in with a JWT still can: the refusal is about the credential.
    assert _client().get("/api/device", headers=_bearer(_jwt(uid))).status_code == 200


def test_a_revoked_phone_is_refused_on_both_paths(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    enrolled = redeem_enrollment_code(_issue(uid), None)
    assert enrolled is not None
    assert revoke_device_token(uid, enrolled.token_id) is True

    headers = _bearer(enrolled.token)
    assert _client().get("/api/me", headers=headers).status_code == 401
    assert _client().get(_INGEST, headers=headers).status_code == 401


def test_the_token_cap_refuses_and_leaves_the_code_unused(configured: None) -> None:  # noqa: ARG001
    uid = _seed_owner()
    for _ in range(_MAX_LIVE_DEVICE_TOKENS):
        mint_device_token(uid, label=None)
    code = _issue(uid)

    with pytest.raises(HTTPException) as refused:
        redeem_enrollment_code(code, None)

    assert refused.value.status_code == 409
    with transaction() as cur:
        cur.execute("SELECT used_at FROM enrollment_code WHERE user_id = %s", (str(uid),))
        assert cur.fetchall() == [(None,)]


def test_the_cli_issues_a_scannable_code_for_the_existing_owner(
    configured: None,  # noqa: ARG001
    capsys: pytest.CaptureFixture[str],
) -> None:
    email = f"owner-{uuid4().hex[:8]}@example.com"
    uid = _seed_owner(email)

    status = enroll.main(
        ["issue", "--email", email.upper(), "--server-url", "https://health.example.com/"]
    )

    assert status == 0
    uri = capsys.readouterr().out.strip().splitlines()[-1]
    assert uri.startswith("healthee://enroll?v=1&server=https%3A%2F%2Fhealth.example.com&code=")
    code = uri.split("code=", 1)[1]
    enrolled = redeem_enrollment_code(code, None)
    assert enrolled is not None
    assert enrolled.user_id == uid


def test_the_cli_revokes_a_phone(configured: None, capsys: pytest.CaptureFixture[str]) -> None:  # noqa: ARG001
    uid = _seed_owner()
    enrolled = redeem_enrollment_code(_issue(uid), None)
    assert enrolled is not None

    assert enroll.main(["revoke", str(enrolled.token_id)]) == 0
    assert enroll.main(["revoke", str(enrolled.token_id)]) == 1
    assert _client().get("/api/me", headers=_bearer(enrolled.token)).status_code == 401
    assert "Revoked" in capsys.readouterr().out


def test_the_cli_creates_an_owner_only_when_asked(
    configured: None,  # noqa: ARG001
    capsys: pytest.CaptureFixture[str],
) -> None:
    email = f"new-{uuid4().hex[:8]}@example.com"
    base = ["issue", "--email", email, "--server-url", "https://h.example.com"]

    assert enroll.main(base) == 2
    assert enroll.main([*base, "--create-owner", "--timezone", "Not/AZone"]) == 2
    assert enroll.main([*base, "--create-owner", "--timezone", "Europe/Berlin"]) == 0
    assert enroll.main([*base, "--create-owner", "--timezone", "Europe/Berlin"]) == 2
    with transaction() as cur:
        cur.execute("SELECT timezone FROM app_user WHERE email = %s", (email,))
        assert cur.fetchall() == [("Europe/Berlin",)]
    capsys.readouterr()
