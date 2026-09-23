"""The app really runs as a non-superuser — proved by connecting as one (6.5b-1, §3.3).

The rest of the suite runs as the ADMIN, so it cannot establish this: every query it
makes would succeed even if the app role had no privileges at all, and every query it
makes will keep succeeding under 6.5b-2's RLS because a superuser ignores policies.
This file is the only place the least-privilege role is actually exercised, so it is
the acceptance bar for the whole phase.

Since 6.5b-2 the WHOLE suite runs as this role (`tests/conftest.py::app_role_pool`),
so it is no longer the only file that exercises it — but it stays the file that
*asserts* it, and the RLS backstop in `test_rls.py` is what the assertions below
underwrite.

Two halves, both required:

* the role can do **everything the app needs** — including writing the `sample`
  hypertable (whose rows land in a `_timescaledb_internal` chunk, where a missing
  grant surfaces as a permission error on an object nobody granted by name) and
  drawing from the BIGSERIAL sequences;
* the role **cannot** do what it must not — no TRUNCATE, no DDL, and `rolsuper` /
  `rolbypassrls` are false, asserted from `pg_roles` directly. That last assertion is
  what 6.5b-2's entire isolation model rests on: policies over a bypassing role are
  decoration.

Auto-skips without a reachable TimescaleDB (same policy as the other integration
tests).
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from psycopg import errors, sql
from tests.conftest import TEST_APP_ROLE
from tests.contracts import seed

from healthee.core import db as db_module
from healthee.core.config import get_settings
from healthee.core.db import admin_connection, tenant_transaction, transaction
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.db import provision_app_role
from healthee.read.today import today_snapshot

pytestmark = pytest.mark.integration


@pytest.fixture
def app_role(db: None, app_role_pool: str | None) -> str:  # noqa: ARG001 — `db` gates reachability
    """The session's least-privilege role, which the app pool is already connected as.

    Provisioning and teardown moved to `conftest.app_role_pool` when 6.5b-2 put the
    WHOLE suite on this role: two fixtures provisioning the same role name would have
    had this file's teardown (`DROP OWNED BY` + `DROP ROLE`) revoke the grants out
    from under every later test in the session.
    """
    assert app_role_pool is not None  # `db` already skipped if the DB is unreachable
    return app_role_pool


def _as_app_role(statement: str, params: tuple[object, ...] = ()) -> list[tuple]:
    """Run one statement on the APP pool (i.e. as the app role) and return its rows.

    No owner is set — everything it asserts is about ROLE privileges (`pg_roles`,
    `pg_tables`, TRUNCATE/DDL denial), which RLS does not touch. The statements that
    do read tenant rows use `tenant_transaction` explicitly.
    """
    with transaction() as cur:
        cur.execute(statement, params)  # pyright: ignore[reportArgumentType] — test-local literals
        return cur.fetchall() if cur.description else []


def _as_owner(statement: str, params: tuple[object, ...] = ()) -> list[tuple]:
    """Run one statement on the APP pool scoped to the sentinel — the RLS-visible path."""
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute(statement, params)  # pyright: ignore[reportArgumentType] — test-local literals
        return cur.fetchall() if cur.description else []


# ── the role is what the 6.5b-2 security model assumes ────────────────────────


def test_app_role_cannot_bypass_rls(app_role: str) -> None:
    """`rolsuper`/`rolbypassrls` false — asked of pg_roles, not of our own intent.

    If this ever flips, every RLS policy 6.5b-2 adds is silently inert and the suite
    would still be green: a bypassing role sees all rows, so the policies pass every
    test while protecting nothing. That is the failure this assertion exists to make
    impossible.
    """
    rows = _as_app_role(
        "SELECT current_user, rolsuper, rolbypassrls, rolcreatedb, rolcreaterole "
        "FROM pg_roles WHERE rolname = current_user"
    )
    assert rows, "the app role has no pg_roles row"
    role, is_super, bypasses_rls, can_create_db, can_create_role = rows[0]
    assert role == app_role, "the pool did not connect as the app role"
    assert is_super is False, "the app role is a SUPERUSER — RLS would be theatre"
    assert bypasses_rls is False, "the app role has BYPASSRLS — RLS would be theatre"
    assert can_create_db is False
    assert can_create_role is False


def test_app_role_does_not_own_the_tables(app_role: str) -> None:
    """Ownership would re-open the hole: an owner needs FORCE to be subject to RLS.

    Because the app role owns nothing, plain `ENABLE ROW LEVEL SECURITY` is enough in
    6.5b-2 — one less thing to get right per table.
    """
    rows = _as_app_role(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tableowner = %s",
        (app_role,),
    )
    assert rows == [], f"the app role owns tables: {rows}"


# ── the role can do everything the application needs ──────────────────────────


def test_app_role_writes_and_reads_the_sample_hypertable(app_role: str) -> None:  # noqa: ARG001
    """The TimescaleDB proof: an INSERT into `sample` lands in a chunk, not in `sample`.

    Chunks live in `_timescaledb_internal` and are never granted by name — their
    privileges are inherited from the parent hypertable. That is documented behaviour,
    but a failure here appears as a permission error on an object the grants never
    mention, so it is proved rather than assumed: the row is written, read back, and
    the chunk it physically landed in is confirmed to exist.
    """
    seed.reset()
    ts = "2031-02-03T04:05:06+00:00"
    _as_owner(
        "INSERT INTO sample (user_id, ts, metric, value) VALUES (%s, %s, 'hr', 61.5)",
        (SENTINEL_USER_ID, ts),
    )
    rows = _as_owner(
        "SELECT value FROM sample WHERE user_id = %s AND metric = 'hr' AND ts = %s",
        (SENTINEL_USER_ID, ts),
    )
    assert rows == [(61.5,)], "the app role could not round-trip a sample"
    chunks = _as_app_role(
        "SELECT chunk_schema, chunk_name FROM timescaledb_information.chunks "
        "WHERE hypertable_name = 'sample'"
    )
    assert chunks, "no chunk was created — the write did not go through the hypertable"
    assert any(schema == "_timescaledb_internal" for schema, _ in chunks)


def test_app_role_can_draw_from_the_bigserial_sequences(app_role: str) -> None:  # noqa: ARG001
    """A table grant alone is not enough for a BIGSERIAL — the sequence needs USAGE.

    `recommendation` is the one the nightly chain writes, so a missing sequence grant
    would surface as the recs job dying every night, not as a failed request.
    """
    seed.reset()
    rows = _as_owner(
        "INSERT INTO recommendation (user_id, date, rank, action, rationale, category, "
        "evidence_grade, research_note_ids, signal_source) VALUES "
        "(%s, DATE '2031-02-03', 1, 'a', 'b', 'sleep', 3, ARRAY['x'], 'test') RETURNING id",
        (SENTINEL_USER_ID,),
    )
    assert rows and rows[0][0] > 0, "the app role could not use recommendation_id_seq"


def test_app_role_serves_a_real_read_path(app_role: str) -> None:  # noqa: ARG001
    """End-to-end: the seed writes through the app pool and /api/today renders from it.

    The fixture's INSERTs run on the app pool too, so this exercises the whole
    read+write surface — not a hand-picked statement that happens to be granted.
    """
    seed.seed_all()
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        payload = today_snapshot(cur, SENTINEL_USER_ID, SENTINEL_TZ)
    steps = next(m for m in payload["metrics"] if m["metric"] == "steps_total")
    assert steps["value"] == pytest.approx(8200.0)
    assert payload["recovery_score"]["recovery"] == pytest.approx(72.0)


# ── the role cannot do what it must not ───────────────────────────────────────


def test_app_role_cannot_truncate(app_role: str) -> None:  # noqa: ARG001
    """TRUNCATE erases a life's health history in one statement. The app never needs it."""
    with pytest.raises(errors.InsufficientPrivilege):
        _as_app_role("TRUNCATE sample")


def test_app_role_cannot_drop_a_table(app_role: str) -> None:  # noqa: ARG001
    with pytest.raises(errors.InsufficientPrivilege):
        _as_app_role("DROP TABLE kv")


def test_app_role_cannot_alter_a_table(app_role: str) -> None:  # noqa: ARG001
    """No DDL — including the ALTER that would disable a 6.5b-2 policy on itself."""
    with pytest.raises(errors.InsufficientPrivilege):
        _as_app_role("ALTER TABLE sample ADD COLUMN sneaky INTEGER")


def test_app_role_cannot_write_the_subscription_table(app_role: str) -> None:  # noqa: ARG001
    """Entitlement is not app-settable — a PRIVILEGE, not a code-review promise (6.6a).

    §12.7's model is that the request path is adversarial-adjacent: every AI gate rests
    on `subscription`, so the role that serves requests must be unable to write it no
    matter what SQL anyone adds later. `provision_app_role._grant_read_only` grants
    SELECT and REVOKEs the rest — and the REVOKE is load-bearing, because
    `ALTER DEFAULT PRIVILEGES` hands the role full DML on any table a new migration
    creates. Without it this test would fail.
    """
    with pytest.raises(errors.InsufficientPrivilege):
        _as_owner(
            "INSERT INTO subscription (user_id, status, current_period_end) "
            "VALUES (%s, 'active', now() + interval '1 year')",
            (SENTINEL_USER_ID,),
        )
    with pytest.raises(errors.InsufficientPrivilege):
        _as_owner(
            "UPDATE subscription SET status = 'active' WHERE user_id = %s", (SENTINEL_USER_ID,)
        )
    with pytest.raises(errors.InsufficientPrivilege):
        _as_owner("DELETE FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))


def test_provisioning_revokes_a_write_privilege_that_was_already_granted(app_role: str) -> None:
    """Prove the REVOKE by DEFEATING it first — the lesson §13 [D3] paid for.

    The assertion above passes on this test database for the wrong reason, and a
    mutation found it: `ALTER DEFAULT PRIVILEGES` only reaches tables created AFTER it
    is set, and the suite runs migrations BEFORE provisioning, so the app role never
    receives DML on `subscription` here and gutting the REVOKE changes nothing.

    Production is the other order. The role and its default privileges already exist,
    a deploy runs `migrate` and then `provision_app_role`, and the new table therefore
    arrives with full DML granted. So this test reproduces THAT: hand the role INSERT,
    confirm it really can write (the premise — a grant that silently failed would make
    the rest of this vacuous), re-provision, and confirm it cannot.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            sql.SQL("GRANT INSERT ON TABLE subscription TO {role}").format(
                role=sql.Identifier(app_role)
            )
        )
    seed.reset()
    _as_owner(
        "INSERT INTO subscription (user_id, status, current_period_end) "
        "VALUES (%s, 'active', now() + interval '1 year')",
        (SENTINEL_USER_ID,),
    )  # the premise: with the grant, the write goes through

    provision_app_role.provision()

    with pytest.raises(errors.InsufficientPrivilege):
        _as_owner(
            "INSERT INTO subscription (user_id, status, current_period_end) "
            "VALUES (%s, 'active', now() + interval '1 year')",
            (SENTINEL_USER_ID,),
        )


def test_app_role_can_read_the_subscription_table(app_role: str) -> None:  # noqa: ARG001
    """…and the gate still works, which the revoke above must not have broken.

    The complement: a REVOKE that took SELECT with it would make `is_premium` raise for
    every request, i.e. lock every paying owner out — a failure mode as bad as the one
    the revoke prevents, and invisible without this half.
    """
    seed.reset()
    rows = _as_owner("SELECT count(*) FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))
    assert rows == [(0,)]


def _insert_enrollment_code() -> None:
    _as_app_role(
        "INSERT INTO enrollment_code (user_id, code_hash, expires_at) "
        "VALUES (%s, %s, now() + interval '10 minutes')",
        (SENTINEL_USER_ID, f"test-{uuid4().hex}"),
    )


def test_app_role_cannot_create_or_delete_enrollment_codes(app_role: str) -> None:  # noqa: ARG001
    """Phones cannot enroll phones — a PRIVILEGE, like `subscription` (0023).

    Redeeming is an UPDATE, which the request path needs; creating a code is how a new
    phone gets a credential, and that stays with the admin CLI on the admin connection.
    """
    seed.reset()
    with pytest.raises(errors.InsufficientPrivilege):
        _insert_enrollment_code()
    with pytest.raises(errors.InsufficientPrivilege):
        _as_app_role("DELETE FROM enrollment_code")
    assert _as_app_role("UPDATE enrollment_code SET used_at = now() WHERE false") == []


def test_provisioning_revokes_an_enrollment_insert_that_was_already_granted(
    app_role: str,
) -> None:
    """The REVOKE proved by defeating it first, for the reason given above for
    `subscription`: production runs `migrate` before `provision_app_role`, so the new
    table arrives with the default DML grant and only the REVOKE takes it back."""
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            sql.SQL("GRANT INSERT ON TABLE enrollment_code TO {role}").format(
                role=sql.Identifier(app_role)
            )
        )
    seed.reset()
    _insert_enrollment_code()  # the premise: with the grant, the write goes through

    provision_app_role.provision()

    with pytest.raises(errors.InsufficientPrivilege):
        _insert_enrollment_code()


def test_app_role_cannot_read_the_migration_ledger(app_role: str) -> None:  # noqa: ARG001
    """Nothing outside the explicit grant list is reachable — the wildcard-grant check.

    `schema_migrations` is the canary: it exists, the admin uses it, and it is
    deliberately not in `_DML_TABLES`. If this ever passes, someone replaced the
    explicit list with `GRANT … ON ALL TABLES`.
    """
    with pytest.raises(errors.InsufficientPrivilege):
        _as_app_role("SELECT version FROM schema_migrations")


# ── operability ───────────────────────────────────────────────────────────────


def test_provision_is_idempotent(app_role: str) -> None:
    """Re-runnable on every deploy — the fixture already provisioned once."""
    assert provision_app_role.provision() == app_role
    assert provision_app_role.provision() == app_role
    rows = _as_app_role("SELECT 1 FROM pg_roles WHERE rolname = current_user")
    assert rows == [(1,)], "the app role stopped working after a re-provision"


def test_provision_refuses_without_a_password(db: None, monkeypatch: pytest.MonkeyPatch) -> None:  # noqa: ARG001
    """A blank password would create a login role anything on the network can use."""
    monkeypatch.setenv("POSTGRES_APP_USER", TEST_APP_ROLE)
    monkeypatch.setenv("POSTGRES_APP_PASSWORD", "")
    get_settings.cache_clear()
    with pytest.raises(Exception, match="together|must both be set"):
        provision_app_role.provision()
    monkeypatch.undo()
    get_settings.cache_clear()


def test_admin_fallback_warns_that_rls_cannot_apply(
    db: None,  # noqa: ARG001 — gates on DB reachability
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """With no app creds the pool still works — but says so, loudly.

    The warning is the only thing standing between "safe transitional deploy" and
    "forgotten forever", and it is what tells the operator whether RLS is in force at
    all. The app creds are unset here to reproduce a deploy that has not yet
    provisioned the role: the pool then falls back to the superuser `healthee`, which
    is the real live-DB finding that started this phase (§3.3a) — so this asserts the
    actual condition rather than a simulated one.

    The pool is rebuilt on the way out, because `db` only closes it: the next test
    must get the session's least-privilege role back, not this admin fallback.
    """
    monkeypatch.delenv("POSTGRES_APP_USER", raising=False)
    monkeypatch.delenv("POSTGRES_APP_PASSWORD", raising=False)
    get_settings.cache_clear()
    db_module.close_pool()
    with caplog.at_level("WARNING"):
        db_module.get_pool()
    warnings = [r.getMessage() for r in caplog.records if r.levelname == "WARNING"]
    assert any("BYPASSES" in message for message in warnings), warnings
    assert any("provision_app_role" in message for message in warnings), warnings
    db_module.close_pool()
    monkeypatch.undo()
    get_settings.cache_clear()
