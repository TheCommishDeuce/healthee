"""The full-history mirror contract (docs/MIRROR.md), property by property.

A digest must move when, and only when, the rows a phone would store move —
corrections and deletions included — must not depend on the database's time zone,
and must never let one owner see another's months.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from healthee.api.routers import mirror as mirror_router
from healthee.core.config import get_settings
from healthee.core.db import tenant_transaction, transaction
from healthee.db import migrate
from healthee.read.mirror import STREAMS, manifest, month_rows

pytestmark = [pytest.mark.integration, pytest.mark.usefixtures("owner_sweep")]

_SECRET = "mirror-integration-secret-0123456789abcdef"


@pytest.fixture
def configured(db: None, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:  # noqa: ARG001
    monkeypatch.setenv("SUPABASE_JWT_SECRET", _SECRET)
    monkeypatch.setenv("SUPABASE_JWT_AUD", "authenticated")
    monkeypatch.delenv("SUPABASE_PROJECT_REF", raising=False)
    get_settings.cache_clear()
    migrate.apply_migrations()
    yield
    get_settings.cache_clear()


def _owner() -> UUID:
    uid = uuid4()
    with transaction() as cur:
        cur.execute("INSERT INTO app_user (id) VALUES (%s)", (str(uid),))
    return uid


def _run(uid: UUID, statement: str, params: tuple[Any, ...]) -> None:
    with tenant_transaction(uid) as cur:
        cur.execute(statement, params)  # pyright: ignore[reportArgumentType] — test literals


def _seed(uid: UUID) -> None:
    for day, value in (("2026-01-15", 7000.0), ("2026-01-20", 8000.0), ("2026-02-03", 9000.0)):
        _run(
            uid,
            "INSERT INTO derived_daily (user_id, day, metric, value) VALUES (%s, %s, %s, %s)",
            (uid, day, "steps_total", value),
        )
    _run(
        uid,
        "INSERT INTO sleep_session (user_id, start_ts, end_ts, score) VALUES (%s, %s, %s, %s)",
        (uid, "2026-01-31T23:30:00Z", "2026-02-01T07:00:00Z", 81),
    )
    _run(
        uid,
        "INSERT INTO weight_log (user_id, ts, kg) VALUES (%s, %s, %s)",
        (uid, "2026-02-10T07:00:00Z", 72.5),
    )


def _manifest(uid: UUID) -> dict[str, Any]:
    with tenant_transaction(uid) as cur:
        return manifest(cur, uid)


def _month(uid: UUID, stream: str, month: str) -> dict[str, Any]:
    with tenant_transaction(uid) as cur:
        return month_rows(cur, uid, stream, month)


def _digests(found: dict[str, Any], stream: str) -> dict[str, str]:
    return {m["month"]: m["digest"] for m in found["streams"][stream]}


def test_an_empty_owner_lists_every_stream_and_no_months(configured: None) -> None:  # noqa: ARG001
    assert _manifest(_owner())["streams"] == {name: [] for name in STREAMS}


def test_the_manifest_digest_is_the_digest_of_the_month_the_phone_stores(
    configured: None,  # noqa: ARG001
) -> None:
    uid = _owner()
    _seed(uid)
    found = _manifest(uid)

    assert [m["month"] for m in found["streams"]["derived_daily"]] == ["2026-01", "2026-02"]
    assert [m["rows"] for m in found["streams"]["derived_daily"]] == [2, 1]
    for stream in ("derived_daily", "sleep_session", "weight_log"):
        for month, digest in _digests(found, stream).items():
            fetched = _month(uid, stream, month)
            assert fetched["digest"] == digest, (stream, month)
            assert len(fetched["items"]) == fetched["rows"]
            # The owner is implied by the credential; it is never data on the phone.
            assert all("user_id" not in item for item in fetched["items"]), stream
    january = _month(uid, "derived_daily", "2026-01")["items"]
    assert january[0] == {
        "day": "2026-01-15",
        "metric": "steps_total",
        "value": 7000.0,
        "flags": {},
    }


def test_a_timestamp_buckets_by_its_utc_month(configured: None) -> None:  # noqa: ARG001
    uid = _owner()
    _seed(uid)
    assert list(_digests(_manifest(uid), "sleep_session")) == ["2026-01"]
    assert _month(uid, "sleep_session", "2026-01")["items"][0]["score"] == 81


def test_a_correction_moves_only_its_own_month(configured: None) -> None:  # noqa: ARG001
    uid = _owner()
    _seed(uid)
    before = _digests(_manifest(uid), "derived_daily")
    _run(
        uid,
        "UPDATE derived_daily SET value = 7100 WHERE user_id = %s AND day = '2026-01-15'",
        (uid,),
    )
    after = _digests(_manifest(uid), "derived_daily")
    assert after["2026-01"] != before["2026-01"]
    assert after["2026-02"] == before["2026-02"]


def test_recomputing_without_changing_the_data_moves_nothing(configured: None) -> None:  # noqa: ARG001
    uid = _owner()
    _seed(uid)
    before = _manifest(uid)
    _run(uid, "UPDATE derived_daily SET derived_at = now() + interval '1 hour'", ())
    assert _manifest(uid) == before


def test_a_deleted_row_moves_its_month_and_an_emptied_month_disappears(
    configured: None,  # noqa: ARG001
) -> None:
    uid = _owner()
    _seed(uid)
    before = _digests(_manifest(uid), "derived_daily")
    _run(uid, "DELETE FROM derived_daily WHERE day = '2026-01-20'", ())
    assert _digests(_manifest(uid), "derived_daily")["2026-01"] != before["2026-01"]
    _run(uid, "DELETE FROM derived_daily WHERE day = '2026-02-03'", ())
    assert "2026-02" not in _digests(_manifest(uid), "derived_daily")


def test_the_digest_does_not_depend_on_the_database_time_zone(configured: None) -> None:  # noqa: ARG001
    uid = _owner()
    _seed(uid)
    baseline = _manifest(uid)
    with tenant_transaction(uid) as cur:
        cur.execute("SET TIME ZONE 'Asia/Kolkata'")
        shifted = manifest(cur, uid)
    assert shifted == baseline


def test_one_owner_never_sees_another_owners_months(configured: None) -> None:  # noqa: ARG001
    owner, other = _owner(), _owner()
    _seed(owner)
    assert _manifest(other)["streams"]["derived_daily"] == []
    assert _month(other, "derived_daily", "2026-01")["items"] == []


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(mirror_router.router)
    return TestClient(app)


def _bearer(uid: UUID) -> dict[str, str]:
    token = jwt.encode(
        {"sub": str(uid), "aud": "authenticated", "exp": datetime.now(tz=UTC) + timedelta(hours=1)},
        _SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def test_the_http_contract(configured: None) -> None:  # noqa: ARG001
    uid = _owner()
    _seed(uid)
    headers = _bearer(uid)
    client = _client()

    assert client.get("/api/mirror/manifest").status_code == 401
    assert client.get("/api/mirror/manifest", headers=headers).json()["version"] == 1
    month = client.get("/api/mirror/weight_log", params={"month": "2026-02"}, headers=headers)
    assert month.json()["items"][0]["kg"] == 72.5
    assert (
        client.get("/api/mirror/sample", params={"month": "2026-02"}, headers=headers).status_code
        == 404
    )
    for bad in ("2026-13", "2026-2", "26-02", "x"):
        assert (
            client.get("/api/mirror/workout", params={"month": bad}, headers=headers).status_code
            == 422
        )
