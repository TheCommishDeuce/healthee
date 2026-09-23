"""Row-Level Security — the isolation BACKSTOP, proved by defeating it (6.5b-2, §3.3).

The durable lesson this repo already paid for once (§13 [D3]): *an isolation mechanism
must be verified by defeating it.* A test that only checks "the right tenant sees their
rows" passes identically against no isolation at all — that is exactly how the §3.3
policies were nearly shipped onto a superuser connection, green and worthless. So the
assertions here are about what a WRONG or ABSENT owner sees, and about the one property
the AST guard (`test_tenant_read_scoping.py`) structurally cannot give us:

    a query with NO `user_id` filter at all is still owner-scoped.

That is the whole reason this phase exists. The explicit `AND user_id = %s` filters stay
(clarity + index use, §5); RLS is what is underneath them when one goes missing.

## The premise these tests rest on

Every assertion below is vacuous if the app pool is connected as a superuser or a
`BYPASSRLS` role — such a role ignores policies entirely, so a leak would return rows
and the test would still pass. `test_the_app_pool_is_never_privileged` asserts that
premise directly, from `pg_roles`, so a future env change cannot silently turn this
whole file into decoration. `tests/conftest.py::app_role_pool` is what makes the
premise true for the session.

Auto-skips without a reachable TimescaleDB (same policy as the other integration tests).
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from psycopg import errors

from healthee.core.db import admin_connection, tenant_transaction, transaction
from healthee.core.tenancy import SENTINEL_USER_ID
from healthee.db import claim_sentinel, migrate

pytestmark = pytest.mark.integration

_OTHER = UUID("dddddddd-dddd-dddd-dddd-dddddddddddd")
_TS = datetime(2997, 5, 6, 7, 8, tzinfo=UTC)
_METRIC = "_rls_probe_hr"

# The identity tables carry NO policy, by decision (§3.3): the app must resolve WHO you
# are before it can know the owner to scope to, and `active_users()` must see every
# owner to sweep them.
_IDENTITY_TABLES = ("app_user", "device_token", "enrollment_code")


@pytest.fixture
def two_owners(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB reachability
    """One `sample` row each for the sentinel and a second owner, at the SAME key.

    Same `(metric, ts)` for both: only `user_id` separates them, so an unscoped read
    cannot accidentally return the right answer — it returns two rows, or the wrong
    owner's.
    """
    migrate.apply_migrations()
    with transaction() as cur:  # app_user is identity — no policy
        cur.execute(
            "INSERT INTO app_user (id, email, timezone) VALUES (%s, %s, 'UTC') "
            "ON CONFLICT (id) DO NOTHING",
            (_OTHER, "rls-other@example.test"),
        )
    for owner, value in ((SENTINEL_USER_ID, 61.0), (_OTHER, 99.0)):
        with tenant_transaction(owner) as cur:
            cur.execute(
                "INSERT INTO sample (user_id, ts, metric, value) VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (user_id, metric, ts) DO UPDATE SET value = EXCLUDED.value",
                (owner, _TS, _METRIC, value),
            )
    yield
    with admin_connection() as conn, conn.cursor() as cur:  # spans both owners
        cur.execute("DELETE FROM sample WHERE metric = %s", (_METRIC,))
        cur.execute("DELETE FROM app_user WHERE id = %s", (_OTHER,))


# ── the premise ───────────────────────────────────────────────────────────────


def test_the_app_pool_is_never_privileged(db: None) -> None:  # noqa: ARG001
    """The pool's role must not be SUPERUSER and must not have BYPASSRLS. **Read this.**

    Asked of `pg_roles`, about the role the pool is ACTUALLY connected as — not of our
    config, and not of our intent. Such a role ignores every policy `0008` creates, so
    if this ever flips, every other test in this file keeps passing while protecting
    nothing, and the "isolation is enforced in two layers" claim in MULTI_USER.md §1
    becomes false without a single test going red.

    That is not hypothetical: `POSTGRES_APP_*` is unset in dev and CI, and the pool
    falls back to the admin superuser when it is. Only `conftest.app_role_pool` makes
    this pass — if someone removes it, this is the test that says so.
    """
    with transaction() as cur:
        cur.execute(
            "SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
        )
        row = cur.fetchone()
    assert row is not None, "the connected role has no pg_roles row"
    role, is_super, bypasses_rls = row
    assert is_super is False, f"the app pool is connected as SUPERUSER {role!r} — RLS is inert"
    assert bypasses_rls is False, f"the app pool role {role!r} has BYPASSRLS — RLS is inert"


# ── THE backstop: the property the AST guard cannot give us ───────────────────


def test_a_query_with_no_owner_filter_is_still_owner_scoped(two_owners: None) -> None:  # noqa: ARG001
    """A `SELECT` with the `user_id` predicate REMOVED still returns only the owner's row.

    This is the entire point of the phase. Both owners hold a row at the same
    `(metric, ts)`, and this query — deliberately written the way a forgetful developer
    would write it — names neither. Without RLS it returns 2 rows; with it, 1.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("SELECT user_id, value FROM sample WHERE metric = %s", (_METRIC,))
        rows = cur.fetchall()
    assert rows == [(SENTINEL_USER_ID, 61.0)], (
        f"an unfiltered read saw across owners: {rows} — the RLS backstop is not working"
    )

    # …and the other owner gets THEIR row from the identical statement. Asserting only
    # one side would pass against a policy that simply hid everyone's rows but one.
    with tenant_transaction(_OTHER) as cur:
        cur.execute("SELECT user_id, value FROM sample WHERE metric = %s", (_METRIC,))
        rows = cur.fetchall()
    assert rows == [(_OTHER, 99.0)]


def test_an_unfiltered_aggregate_is_owner_scoped(two_owners: None) -> None:  # noqa: ARG001
    """The same property for a COUNT — the shape where a leak is silent, not visible.

    A leaked row in a list is at least a visible wrong row; a leaked row in an average
    or a baseline is a plausible-looking number computed over a stranger's body. That
    is the silent wrongness this product exists to refuse.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("SELECT count(*), avg(value) FROM sample WHERE metric = %s", (_METRIC,))
        count, average = cur.fetchone() or (None, None)
    assert count == 1, "an unfiltered aggregate pooled another owner's rows"
    assert average == pytest.approx(61.0), "the average was computed across owners"


# ── fails closed ──────────────────────────────────────────────────────────────


def test_no_owner_set_returns_nothing_and_does_not_error(two_owners: None) -> None:  # noqa: ARG001
    """A tenant read on a plain `transaction()` returns 0 rows, silently. By design.

    Failing closed rather than raising is the deliberate choice (an error would mean an
    unset GUC leaks rows until someone notices), and it is also the dangerous one: a
    tenant query left on `transaction()` shows a user "no data" instead of breaking.
    That trade-off is why the whole suite runs as this role — so the mistake fails a
    test here rather than reaching someone's health history.
    """
    with transaction() as cur:
        cur.execute("SELECT count(*) FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.fetchone() == (0,), "an owner-less read saw rows — RLS is not applying"


def test_an_empty_owner_guc_returns_nothing_and_does_not_error(two_owners: None) -> None:  # noqa: ARG001
    """The `NULLIF` case — pins the one subtlety the policy would be wrong without.

    Once a custom GUC has been touched in a session, `current_setting(x, true)` returns
    the EMPTY STRING, not NULL. A policy comparing against a bare `''::uuid` therefore
    raises `invalid input syntax for type uuid` instead of failing closed — an error on
    a live read path, and a policy that fails open the moment someone "fixes" the error
    by catching it. `NULLIF(…, '')` turns it back into NULL, and `user_id = NULL` is
    NULL ⇒ no rows, no error.

    A pooled connection reaches this state constantly: `tenant_transaction` sets the
    GUC, the transaction ends, the setting reverts to '' — and the next borrower of
    that connection sees exactly what is asserted here.
    """
    with transaction() as cur:
        cur.execute("SELECT set_config('healthee.user_id', '', true)")
        cur.execute("SELECT count(*) FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.fetchone() == (0,), "an empty owner GUC saw rows"


def test_the_owner_does_not_outlive_its_transaction(two_owners: None) -> None:  # noqa: ARG001
    """`is_local=true` means the owner reverts at COMMIT — it cannot leak across borrows.

    The pool hands the same physical connection to the next caller. If the owner were
    set for the SESSION instead, that caller would silently inherit it and read someone
    else's data — the exact leak RLS is here to prevent, reintroduced by the mechanism
    meant to stop it.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("SELECT count(*) FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.fetchone() == (1,)
    # A fresh transaction on the pool: whatever connection comes back, no owner is set.
    with transaction() as cur:
        cur.execute("SELECT current_setting('healthee.user_id', true)")
        assert (cur.fetchone() or ("",))[0] in ("", None), "the owner outlived its transaction"


# ── writes: the WITH CHECK half ───────────────────────────────────────────────


def test_a_cross_owner_write_is_denied(two_owners: None) -> None:  # noqa: ARG001
    """Writing a row owned by B while scoped to A raises, rather than landing.

    The read half of a policy cannot catch this: a `USING`-only policy governs
    SELECT/UPDATE/DELETE and leaves INSERT completely ungoverned, so a compromised or
    buggy writer could attribute rows to anyone. `FOR ALL` + `WITH CHECK` is what makes
    the write side real.
    """
    with (
        pytest.raises(errors.InsufficientPrivilege, match="row-level security"),
        tenant_transaction(SENTINEL_USER_ID) as cur,
    ):
        cur.execute(
            "INSERT INTO sample (user_id, ts, metric, value) VALUES (%s, %s, %s, 1.0)",
            (_OTHER, _TS + timedelta(minutes=1), _METRIC),
        )


def test_a_write_without_an_owner_is_denied_by_the_policy(db: None) -> None:  # noqa: ARG001
    """An owner-less INSERT is refused by the POLICY, before NOT NULL is ever consulted.

    `0007` made the column mandatory so a forgotten owner is loud; `0008` now catches it
    one step earlier on the app pool (`user_id = NULL` is NULL, never true). Both
    guarantees are real and independent — the NOT NULL half is asserted from the admin
    in `test_tenant_column.py`, where the policy cannot mask it.
    """
    migrate.apply_migrations()
    with (
        pytest.raises(errors.InsufficientPrivilege, match="row-level security"),
        transaction() as cur,
    ):
        cur.execute("INSERT INTO kv (key, value) VALUES ('_rls_no_owner', 'v')")


def test_an_upsert_under_the_owner_still_works(two_owners: None) -> None:  # noqa: ARG001
    """The ordinary path is unaffected: an ON CONFLICT upsert under the owner succeeds.

    Without this, every test above would also pass against a policy that simply denied
    all writes — "it refuses" is only the right behaviour if the correct write doesn't.
    Every writer in the codebase is an upsert, so this is the shape that matters.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute(
            "INSERT INTO sample (user_id, ts, metric, value) VALUES (%s, %s, %s, 77.0) "
            "ON CONFLICT (user_id, metric, ts) DO UPDATE SET value = EXCLUDED.value "
            "RETURNING value",
            (SENTINEL_USER_ID, _TS, _METRIC),
        )
        assert cur.fetchone() == (77.0,), "an owner's own upsert was blocked by the policy"


def test_a_cross_owner_update_moves_nothing(two_owners: None) -> None:  # noqa: ARG001
    """An UPDATE with no owner filter cannot reach the other owner's row.

    UPDATE is governed by USING (which rows it may see) and WITH CHECK (what it may
    leave behind). Here the first is what matters: B's row is invisible, so the
    statement matches only A's — a mass-update bug is bounded to its own tenant.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("UPDATE sample SET value = 1.0 WHERE metric = %s", (_METRIC,))
        assert cur.rowcount == 1, f"an unfiltered UPDATE touched {cur.rowcount} owners' rows"
    with tenant_transaction(_OTHER) as cur:
        cur.execute("SELECT value FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.fetchone() == (99.0,), "the other owner's row was modified"


def test_a_cross_owner_delete_removes_nothing(two_owners: None) -> None:  # noqa: ARG001
    """The same for DELETE — the shape that would silently destroy a life's history."""
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("DELETE FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.rowcount == 1, f"an unfiltered DELETE reached {cur.rowcount} owners' rows"
    with tenant_transaction(_OTHER) as cur:
        cur.execute("SELECT count(*) FROM sample WHERE metric = %s", (_METRIC,))
        assert cur.fetchone() == (1,), "the other owner's row was deleted"


# ── completeness: every tenant table, discovered from the catalog ─────────────


def _tenant_tables() -> list[str]:
    with admin_connection() as conn, conn.cursor() as cur:
        return claim_sentinel.tenant_tables(cur)


def test_every_tenant_table_has_rls_enabled_and_exactly_one_policy(db: None) -> None:  # noqa: ARG001
    """All 18, driven off the DATABASE's own list of what references `app_user`.

    Never a list hand-copied into the test: a tenant table added by a future migration
    is covered by this assertion the day it is created, and the failure names it. A
    hand-written list would silently keep passing while the new table sat unprotected —
    the same reasoning `claim_sentinel`'s post-check is built on.
    """
    migrate.apply_migrations()
    tables = _tenant_tables()
    assert len(tables) == 19, (
        f"expected the 18 tenant tables (§3.2 + subscription + device_daily_total), "
        f"found {len(tables)}: {tables}"
    )
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT c.relname, c.relrowsecurity, count(p.polname) "
            "FROM pg_class c LEFT JOIN pg_policy p ON p.polrelid = c.oid "
            "WHERE c.relname = ANY(%s) GROUP BY c.relname, c.relrowsecurity",
            (tables,),
        )
        found = {name: (enabled, policies) for name, enabled, policies in cur.fetchall()}
    assert set(found) == set(tables)
    for table in tables:
        enabled, policies = found[table]
        assert enabled is True, f"{table} does not have ROW LEVEL SECURITY enabled"
        assert policies == 1, f"{table} has {policies} policies — expected exactly 1"


def test_the_identity_tables_have_no_policy(db: None) -> None:  # noqa: ARG001
    """`app_user` / `device_token` are deliberately NOT policied (§3.3) — pin the decision.

    The auth path has to resolve who you are BEFORE it knows an owner to scope to, and
    the scheduler's `active_users()` sweep has to see every owner or their nightly chain
    silently stops. A policy here would fail both closed — which reads as "the app is
    broken" rather than "the app is secure". Their protection is the grant list in
    `provision_app_role`, not RLS.
    """
    migrate.apply_migrations()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT c.relname, c.relrowsecurity, count(p.polname) "
            "FROM pg_class c LEFT JOIN pg_policy p ON p.polrelid = c.oid "
            "WHERE c.relname = ANY(%s) GROUP BY c.relname, c.relrowsecurity",
            (list(_IDENTITY_TABLES),),
        )
        for name, enabled, policies in cur.fetchall():
            assert enabled is False, f"{name} has RLS enabled — the auth path cannot resolve users"
            assert policies == 0, f"{name} carries {policies} policies"


def test_the_admin_is_not_subject_to_the_policies(db: None) -> None:  # noqa: ARG001
    """`0008` does not FORCE, so the OWNER still sees every row — which is load-bearing.

    `migrate`, `claim_sentinel`, `provision_app_role` and the test reset all have to see
    across owners. `claim_sentinel` is the sharpest case: its FK cascades would still
    move the rows under RLS, but its verification SELECTs would be filtered to nothing
    and report a PARTIAL re-key as a success. That is why it is on the admin, and this
    is the property that makes that work.
    """
    migrate.apply_migrations()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'sample'")
        assert cur.fetchone() == (False,), "FORCE would subject the admin to the policies"
