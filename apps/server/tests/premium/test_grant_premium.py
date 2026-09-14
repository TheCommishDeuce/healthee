"""``db/grant_premium.py`` — the hand path that makes the gate deployable (6.6a).

This is the module that stands between "ship the paywall" and "the live owner silently
loses their whole AI layer on the next deploy", so it is tested the way
``claim_sentinel`` is: the DRY RUN must change nothing, the refusals must refuse, and
the applied grant must be the thing ``is_premium`` then reads.

It is the one writer of ``subscription`` besides 6.6b's future webhook, and it runs on
the ADMIN connection — the app role has no write privilege there at all
(``tests/db/test_app_role.py``).
"""

from __future__ import annotations

from collections.abc import Iterator
from uuid import uuid4

import pytest
from tests.contracts.seed import seed_all

from healthee.core.db import admin_connection
from healthee.core.entitlement import is_premium
from healthee.core.tenancy import SENTINEL_USER_ID
from healthee.db import grant_premium

pytestmark = pytest.mark.integration


@pytest.fixture
def clean(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB reachability
    """A seeded owner with NO entitlement — the state a fresh deploy is really in."""
    seed_all()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))
    yield


def test_the_default_run_is_a_dry_run_that_changes_nothing(clean: None) -> None:  # noqa: ARG001
    """An operator's FIRST run can never be the real one (claim_sentinel's rule)."""
    assert grant_premium.main([str(SENTINEL_USER_ID), "--months", "12"]) == 0
    assert is_premium(SENTINEL_USER_ID) is False


def test_apply_grants_the_entitlement_the_gate_then_reads(clean: None) -> None:  # noqa: ARG001
    """End to end: the CLI writes the row, and `is_premium` — the gate's own function,
    not a re-implementation of its rule — says yes."""
    assert grant_premium.main([str(SENTINEL_USER_ID), "--months", "12", "--apply"]) == 0
    assert is_premium(SENTINEL_USER_ID) is True


def test_the_sentinel_owner_can_be_granted_despite_having_no_email(clean: None) -> None:  # noqa: ARG001
    """The account that actually needs this on deploy day has `email = NULL` (§8).

    A refusal keyed on a missing email would refuse exactly the one owner the module
    exists for — and it would look like a sensible safety check while doing it.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT email FROM app_user WHERE id = %s", (SENTINEL_USER_ID,))
        row = cur.fetchone()
    assert row is not None and row[0] is None
    assert grant_premium.main([str(SENTINEL_USER_ID), "--months", "1", "--apply"]) == 0
    assert is_premium(SENTINEL_USER_ID) is True


def test_it_refuses_an_owner_who_has_never_signed_in(clean: None) -> None:  # noqa: ARG001
    """An unverified UUID is a typo away from paying for a stranger.

    A FRESH uuid4, not a memorable constant: the first draft used
    ``cccccccc-…-cccc``, which `tests/integration/test_ingest_attribution.py` also uses
    as a real owner — so the id existed, the grant succeeded, and the test failed. A
    literal that another suite happens to provision would otherwise have inverted this
    assertion silently the day the two files were run in the other order.
    """
    stranger = uuid4()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 FROM app_user WHERE id = %s", (stranger,))
        assert cur.fetchone() is None, "the premise failed — this owner exists"

    assert grant_premium.main([str(stranger), "--months", "12", "--apply"]) == 2
    assert is_premium(stranger) is False


def test_it_refuses_a_grant_with_no_term(clean: None) -> None:  # noqa: ARG001
    """`--months` has no default on purpose — "granted once, forgotten" is the loophole."""
    assert grant_premium.main([str(SENTINEL_USER_ID), "--apply"]) == 2
    assert is_premium(SENTINEL_USER_ID) is False


def test_revoke_ends_access_now_and_keeps_the_row(clean: None) -> None:  # noqa: ARG001
    """History of who had access when is worth keeping, so it writes `canceled`."""
    grant_premium.main([str(SENTINEL_USER_ID), "--months", "12", "--apply"])
    assert is_premium(SENTINEL_USER_ID) is True

    assert grant_premium.main([str(SENTINEL_USER_ID), "--revoke", "--apply"]) == 0
    assert is_premium(SENTINEL_USER_ID) is False
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT status FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))
        row = cur.fetchone()
    assert row is not None and row[0] == "canceled"


def test_a_second_grant_replaces_the_first_rather_than_erroring(clean: None) -> None:  # noqa: ARG001
    """Re-runnable: renewing a comp is the same command with a new term."""
    grant_premium.main([str(SENTINEL_USER_ID), "--months", "1", "--apply"])
    grant_premium.main([str(SENTINEL_USER_ID), "--months", "24", "--apply", "--by", "fable"])
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT plan, granted_by FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,)
        )
        row = cur.fetchone()
    assert row == ("comp_24mo", "fable")


# ── the per-owner coach cap (0022) ────────────────────────────────────────────


def _row() -> tuple[object, ...] | None:
    """``(plan, current_period_end, coach_questions)`` for the seeded owner, or None."""
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT plan, current_period_end, coach_questions FROM subscription WHERE user_id = %s",
            (SENTINEL_USER_ID,),
        )
        return cur.fetchone()


def test_a_grant_can_set_the_owner_coach_cap(clean: None) -> None:  # noqa: ARG001
    owner = str(SENTINEL_USER_ID)
    assert grant_premium.main([owner, "--months", "12", "--coach-questions", "20", "--apply"]) == 0
    row = _row()
    assert row is not None
    assert row[2] == 20


def test_a_cap_only_change_leaves_the_term_exactly_as_found(clean: None) -> None:  # noqa: ARG001
    """How an operator lifts their own cap without re-dating a comp that runs to 2036."""
    owner = str(SENTINEL_USER_ID)
    grant_premium.main([owner, "--months", "12", "--apply"])
    before = _row()
    assert grant_premium.main([owner, "--coach-questions", "unlimited", "--apply"]) == 0
    after = _row()
    assert before is not None and after is not None
    assert after[:2] == before[:2], "a cap-only change re-dated or re-planned the grant"
    assert after[2] == 0


def test_renewing_without_the_flag_keeps_the_cap(clean: None) -> None:  # noqa: ARG001
    """A renewal that nulled the cap would hand a capped guest the default on every renew."""
    owner = str(SENTINEL_USER_ID)
    grant_premium.main([owner, "--months", "1", "--coach-questions", "5", "--apply"])
    grant_premium.main([owner, "--months", "24", "--apply"])
    row = _row()
    assert row is not None
    assert row[0] == "comp_24mo"
    assert row[2] == 5, "renewing the term quietly reset the owner's cap"


def test_default_hands_the_owner_back_to_the_deployment_cap(clean: None) -> None:  # noqa: ARG001
    owner = str(SENTINEL_USER_ID)
    grant_premium.main([owner, "--months", "12", "--coach-questions", "5", "--apply"])
    assert grant_premium.main([owner, "--coach-questions", "default", "--apply"]) == 0
    row = _row()
    assert row is not None
    assert row[2] is None


def test_a_cap_only_change_refuses_an_owner_with_no_grant(clean: None) -> None:  # noqa: ARG001
    """There is no grant to cap — and a refusal must not leave a half-row behind."""
    owner = str(SENTINEL_USER_ID)
    assert grant_premium.main([owner, "--coach-questions", "20", "--apply"]) == 2
    assert _row() is None, "a refused cap change still created a subscription row"


@pytest.mark.parametrize("raw", ["-1", "lots", ""])
def test_it_refuses_a_cap_that_is_not_a_cap(clean: None, raw: str) -> None:  # noqa: ARG001
    owner = str(SENTINEL_USER_ID)
    assert grant_premium.main([owner, "--months", "12", "--coach-questions", raw, "--apply"]) == 2
    assert _row() is None, f"a refused cap {raw!r} still wrote the grant"


def test_the_dry_run_with_a_cap_writes_nothing(clean: None) -> None:  # noqa: ARG001
    owner = str(SENTINEL_USER_ID)
    assert grant_premium.main([owner, "--months", "12", "--coach-questions", "3"]) == 0
    assert _row() is None
