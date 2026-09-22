"""The sentinel → real-owner re-key (`db/claim_sentinel.py`, 6.4c / MULTI_USER.md §8).

The one-off that hands the pre-auth data to the real Supabase owner. It is destructive
and run once, so what is tested is not just "it moves rows" but every way it must
REFUSE, and the post-check that makes a partial move impossible.

Every owner's whole health history rides on this, so the "no row is left behind" proof
is driven off `claim_sentinel.tenant_tables()` — the database's own list of what
references `app_user` — never a list hand-copied into the test. A table added next
month is covered by these assertions the day it is created.

The seed helpers live in `_claim_seed.py` and the `claimable` fixture in `conftest.py`
(the 400-line gate); this module is the assertions.

Everything here runs on the ADMIN connection, matching the tool it tests (6.5b-2,
`core.db.admin_connection`'s caller list). That is not convenience: every assertion
below is of the form "count the rows owned by X, then by Y", which no RLS-scoped
connection can make — it sees exactly one owner by construction. Verifying the re-key
on the app role would filter the post-check down to zero rows and report a partial
claim as a success, which is the specific failure `claim_sentinel` exists to prevent.

Auto-skips without a reachable TimescaleDB (same policy as the other integration
tests).
"""

from __future__ import annotations

from uuid import UUID

import pytest
from tests.db._claim_seed import DAY, MARK, OCCUPIED, TARGET, TARGET_EMAIL, TARGET_TZ, provision

from healthee.core.db import admin_connection
from healthee.core.tenancy import SENTINEL_USER_ID
from healthee.db import claim_sentinel
from healthee.db.claim_sentinel import ClaimRefusedError

pytestmark = pytest.mark.integration

# The 18 tenant tables: MULTI_USER.md §3.2's sixteen plus `subscription` (§12.2, added
# by 0011) and `device_daily_total` (0017). NOT the tool's source of truth — the tool asks
# the database. This is the cross-check that the discovery finds them all, so a discovery
# query that quietly matched nothing could not report green.
#
# `subscription` belongs in the claim for the same reason every other row does: an
# owner's entitlement is theirs, and a re-key that moved their health data but left
# their subscription behind would take away the thing they paid for.
_EXPECTED_TENANT_TABLES = {
    "sample", "sleep_session", "workout", "derived_daily", "weight_log", "kv",
    "manual_entry", "illness_flag", "recommendation", "finding", "challenge",
    "program", "challenge_outcome", "gps_track", "gps_point", "profile",
    "subscription", "device_daily_total", "coach_commitment",
}  # fmt: skip


def _owned(cur, user_id: UUID) -> dict[str, int]:
    """Per-table row counts for an owner, straight from the canonical table list."""
    tables = claim_sentinel.tenant_tables(cur)
    return {t: claim_sentinel._count_rows(cur, t, user_id) for t in tables}


# ── the canonical table list ───────────────────────────────────────────────────


def test_the_tenant_table_list_is_discovered_not_hand_written(claimable: None) -> None:  # noqa: ARG001
    """Discovery must find all 19 tenant tables — and exclude identity + chunks.

    If this query ever matched nothing, every "no rows left behind" assertion below
    would vacuously pass while the tool moved half a person's history.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        assert set(claim_sentinel.tenant_tables(cur)) == _EXPECTED_TENANT_TABLES
        # device_token references app_user but holds credentials, not owned data.
        assert "device_token" in claim_sentinel.referencing_tables(cur)
        assert "device_token" not in claim_sentinel.tenant_tables(cur)
        assert "enrollment_code" in claim_sentinel.referencing_tables(cur)
        assert "enrollment_code" not in claim_sentinel.tenant_tables(cur)


# ── dry run ────────────────────────────────────────────────────────────────────


def test_dry_run_changes_nothing(claimable: None) -> None:  # noqa: ARG001
    """The default must be inert — an operator's first run can never be the real one."""
    with admin_connection() as conn, conn.cursor() as cur:
        before = _owned(cur, SENTINEL_USER_ID)

    claim_sentinel.claim(TARGET)  # no --apply

    with admin_connection() as conn, conn.cursor() as cur:
        assert _owned(cur, SENTINEL_USER_ID) == before
        assert not any(_owned(cur, TARGET).values()), "a dry run moved rows"
        cur.execute("SELECT 1 FROM app_user WHERE id = %s", (SENTINEL_USER_ID,))
        assert cur.fetchone() is not None, "a dry run removed the sentinel"


def test_dry_run_reports_accurate_counts(claimable: None) -> None:  # noqa: ARG001
    """The report is the operator's only view of the blast radius — it must be exact."""
    with admin_connection() as conn, conn.cursor() as cur:
        expected = {t: n for t, n in _owned(cur, SENTINEL_USER_ID).items() if n}

    plan = claim_sentinel.claim(TARGET)

    assert plan is not None
    assert plan.counts == expected
    assert set(plan.counts) == _EXPECTED_TENANT_TABLES, "a tenant table was left out"
    assert plan.total == sum(expected.values())
    assert plan.email == TARGET_EMAIL  # the operator confirms WHO before --apply


# ── apply ──────────────────────────────────────────────────────────────────────


def test_apply_moves_every_table(claimable: None) -> None:  # noqa: ARG001
    """Every table's rows land on the target — counts preserved exactly."""
    with admin_connection() as conn, conn.cursor() as cur:
        before = _owned(cur, SENTINEL_USER_ID)

    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        assert _owned(cur, TARGET) == before


def test_no_row_anywhere_still_belongs_to_the_sentinel(claimable: None) -> None:  # noqa: ARG001
    """THE proof, over the database's own list of everything referencing app_user."""
    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        stragglers = {
            t: n
            for t in claim_sentinel.referencing_tables(cur)
            if (n := claim_sentinel._count_rows(cur, t, SENTINEL_USER_ID))
        }
        assert stragglers == {}
        cur.execute("SELECT 1 FROM app_user WHERE id = %s", (SENTINEL_USER_ID,))
        assert cur.fetchone() is None, "the sentinel app_user row survived"


def test_the_target_keeps_their_real_email_and_timezone(claimable: None) -> None:  # noqa: ARG001
    """The re-keyed row must wear the OWNER's identity, not the sentinel's.

    A naive cascade leaves `email = NULL` and `Asia/Kolkata` on the surviving row: the
    real email is lost, and — worse — every day boundary, window and "today" for that
    owner silently resolves in a timezone they do not live in.
    """
    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT email, timezone FROM app_user WHERE id = %s", (TARGET,))
        row = cur.fetchone()
    assert row is not None, "the target's app_user row is gone"
    assert row[0] == TARGET_EMAIL, "the sentinel's NULL email overwrote the real one"
    assert row[1] == TARGET_TZ, "the re-keyed owner inherited the sentinel's timezone"


def test_the_sentinels_device_tokens_move_too(claimable: None) -> None:  # noqa: ARG001
    """0006's regression: `device_token`'s FK was ON UPDATE NO ACTION.

    With that FK the re-key does not skip tokens — it ERRORS outright, making the
    one-off unrunnable for any owner who ever paired a device. This is the test that
    fails without the migration.
    """
    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT user_id FROM device_token WHERE label = %s", (MARK,))
        row = cur.fetchone()
    assert row is not None, "the device token was destroyed by the re-key"
    assert row[0] == TARGET


def test_a_target_device_token_survives_the_claim(claimable: None) -> None:  # noqa: ARG001
    """A token the target paired BEFORE claiming must not be cascade-deleted.

    The claim frees the target's primary key by deleting their app_user row; done
    naively that takes their device tokens with it and silently breaks the app they
    just paired.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO device_token (user_id, token_hash, label) VALUES (%s, %s, %s)",
            (TARGET, f"{MARK}-target", MARK),
        )

    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT user_id FROM device_token WHERE token_hash = %s", (f"{MARK}-target",))
        row = cur.fetchone()
    assert row is not None, "the target's own device token was destroyed"
    assert row[0] == TARGET


def test_a_target_enrollment_code_survives_the_claim(claimable: None) -> None:  # noqa: ARG001
    """The same for the target's enrollment codes (0023): they record which code
    enrolled which phone, and deleting the target's row must not cascade them away."""
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO enrollment_code (user_id, code_hash, label, expires_at) "
            "VALUES (%s, %s, %s, now() + interval '10 minutes')",
            (TARGET, f"{MARK}-code", MARK),
        )

    claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT user_id FROM enrollment_code WHERE code_hash = %s", (f"{MARK}-code",))
        row = cur.fetchone()
    assert row is not None, "the target's enrollment code was destroyed"
    assert row[0] == TARGET


# ── entitlement: granted before the claim (C1) ─────────────────────────────────


def _grant(cur, user_id: UUID) -> None:
    """Comp `user_id`, the way `db/grant_premium.py` does — an upsert on the PK."""
    cur.execute(
        "INSERT INTO subscription (user_id, status, plan, current_period_end, granted_by) "
        "VALUES (%s, 'active', 'c1-test', now() + interval '1 year', %s) "
        "ON CONFLICT (user_id) DO UPDATE SET plan = EXCLUDED.plan, "
        "granted_by = EXCLUDED.granted_by",
        (user_id, MARK),
    )


def test_an_entitled_target_is_not_refused_as_owning_health_data(
    claimable: None,  # noqa: ARG001
) -> None:
    """The C1 sequence, end to end: sign in, get comped, then claim.

    `grant_premium` requires an `app_user` row, so a grant BEFORE the claim is the
    natural order — and it used to make the claim refuse forever, with the wrong
    diagnosis: it told the operator their target owned health data when the only row
    they owned was an entitlement. There was no shipped way back, either: `--revoke`
    writes `status = 'canceled'` through the same upsert and nothing deletes the row.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        _grant(cur, TARGET)

    claim_sentinel.claim(TARGET, apply=True)  # must not raise

    with admin_connection() as conn, conn.cursor() as cur:
        assert not any(_owned(cur, SENTINEL_USER_ID).values())
        cur.execute("SELECT plan FROM subscription WHERE user_id = %s", (TARGET,))
        row = cur.fetchone()
    assert row is not None, "the target's entitlement was cascade-deleted by the re-key"
    assert row[0] == "c1-test", "the sentinel's row survived instead of the target's own"


def test_health_data_still_refuses_even_beside_an_entitlement(
    claimable: None,  # noqa: ARG001
) -> None:
    """The refusal is narrowed, not removed — one derived row still stops the claim."""
    with admin_connection() as conn, conn.cursor() as cur:
        provision(cur, OCCUPIED, "occupied@example.test", TARGET_TZ)
        _grant(cur, OCCUPIED)
        cur.execute(
            "INSERT INTO derived_daily (user_id, day, metric, value) VALUES (%s, %s, %s, 9) "
            "ON CONFLICT DO NOTHING",
            (OCCUPIED, DAY, MARK),
        )

    with pytest.raises(ClaimRefusedError, match="already owns data"):
        claim_sentinel.claim(OCCUPIED, apply=True)


def test_the_superseded_entitlement_is_announced_before_apply(
    claimable: None,  # noqa: ARG001
) -> None:
    """One row per owner, so one is dropped — and the operator is told which, first.

    `subscription.user_id` is the PRIMARY KEY: the two rows cannot be merged and the
    target's wins. Silently is the one way that must not happen, so the dry run carries
    the flag and `_report` prints it.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        _grant(cur, TARGET)

    dry = claim_sentinel.claim(TARGET)
    assert dry is not None and dry.entitlement_superseded is True

    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))
        assert (cur.fetchone() or (0,))[0] == 1, "the dry run changed something"


def test_the_sentinels_entitlement_still_moves_when_the_target_has_none(
    claimable: None,  # noqa: ARG001
) -> None:
    """The unchanged case, kept honest: an owner's entitlement rides the re-key.

    Nothing about C1 may take away the thing the sentinel was paying for — the
    `_NON_HEALTH_TABLES` split exists precisely so `subscription` stays a tenant table
    the tool moves and reports, and only stops being a reason to refuse.
    """
    dry = claim_sentinel.claim(TARGET)
    assert dry is not None
    assert dry.counts.get("subscription") == 1, "the plan stopped reporting the entitlement"
    assert dry.entitlement_superseded is False

    claim_sentinel.claim(TARGET, apply=True)
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM subscription WHERE user_id = %s", (TARGET,))
        assert (cur.fetchone() or (0,))[0] == 1


# ── refusals + idempotence ─────────────────────────────────────────────────────


def test_refuses_when_the_target_already_owns_data(claimable: None) -> None:  # noqa: ARG001
    """Two owners with data is a merge — a judgement call this tool must not make."""
    with admin_connection() as conn, conn.cursor() as cur:
        provision(cur, OCCUPIED, "occupied@example.test", TARGET_TZ)
        cur.execute(
            "INSERT INTO derived_daily (user_id, day, metric, value) VALUES (%s, %s, %s, 9) "
            "ON CONFLICT DO NOTHING",
            (OCCUPIED, DAY, MARK),
        )

    with pytest.raises(ClaimRefusedError, match="already owns data"):
        claim_sentinel.claim(OCCUPIED, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        assert any(_owned(cur, SENTINEL_USER_ID).values()), "a refused claim moved rows"


def test_refuses_an_unknown_target(claimable: None) -> None:  # noqa: ARG001
    """A UUID that never signed in may be a typo — and a typo'd claim is not undoable."""
    with pytest.raises(ClaimRefusedError, match="never signed in"):
        claim_sentinel.claim(UUID("99999999-9999-9999-9999-999999999999"), apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        assert any(_owned(cur, SENTINEL_USER_ID).values())


def test_refuses_the_sentinel_as_its_own_target(claimable: None) -> None:  # noqa: ARG001
    with pytest.raises(ClaimRefusedError, match="the sentinel itself"):
        claim_sentinel.claim(SENTINEL_USER_ID, apply=True)


def test_a_malformed_uuid_never_reaches_the_database() -> None:
    """argparse rejects it at the boundary — exit 2, no connection attempted."""
    with pytest.raises(SystemExit) as exc:
        claim_sentinel.main(["not-a-uuid", "--apply"])
    assert exc.value.code == 2


def test_rerunning_after_a_successful_claim_is_a_clean_no_op(claimable: None) -> None:  # noqa: ARG001
    """Idempotent: with no sentinel row there is nothing to move, and that is not an error."""
    claim_sentinel.claim(TARGET, apply=True)

    assert claim_sentinel.claim(TARGET, apply=True) is None
    assert claim_sentinel.main([str(TARGET), "--apply"]) == 0


def test_the_cli_refuses_with_a_nonzero_exit(claimable: None) -> None:  # noqa: ARG001
    """A refusal must be visible to an operator's shell, not just to a log reader."""
    assert claim_sentinel.main([str(UUID(int=12345))]) == 2
    assert claim_sentinel.main([str(TARGET)]) == 0  # the dry run itself is fine


def test_a_failed_post_check_rolls_the_whole_rekey_back(
    claimable: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The net itself: if verification fails, NOTHING moves — never a half-claim.

    A partial re-key would scatter one person's health history across two owners, and
    every derived number computed afterwards would be quietly wrong rather than
    missing. Simulated by forcing the post-check to fail on an otherwise good claim.
    """

    def boom(_cur) -> None:
        raise ClaimRefusedError("post-check FAILED — simulated straggler")

    monkeypatch.setattr(claim_sentinel, "_verify", boom)
    with admin_connection() as conn, conn.cursor() as cur:
        before = _owned(cur, SENTINEL_USER_ID)

    with pytest.raises(ClaimRefusedError, match="simulated straggler"):
        claim_sentinel.claim(TARGET, apply=True)

    with admin_connection() as conn, conn.cursor() as cur:
        assert _owned(cur, SENTINEL_USER_ID) == before, "a failed post-check left data moved"
        assert not any(_owned(cur, TARGET).values())
        cur.execute("SELECT email FROM app_user WHERE id = %s", (TARGET,))
        row = cur.fetchone()
    assert row is not None and row[0] == TARGET_EMAIL, "the target's row was not restored"
