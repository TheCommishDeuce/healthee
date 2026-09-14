"""One owner's coach cap overrides the deployment's, in both directions (0022).

``PREMIUM_COACH_QUESTIONS`` alone could say "every premium owner gets 20" or "every one
is unlimited", and nothing in between: an operator opening a box to guests had to cap
themselves to cap the guests. ``subscription.coach_questions`` is the in-between.

The tests that matter are the two CROSSINGS — a capped deployment whose owner is
unlimited, and an unlimited deployment with a capped guest — because a resolution that
could only narrow, or only widen, passes exactly half of them.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from tests.insights._stub import StubLLM
from tests.premium.conftest import AUTH

from healthee.api import gate
from healthee.core.config import get_settings
from healthee.core.db import admin_connection
from healthee.core.entitlement import Subscription, evaluate
from healthee.core.tenancy import SENTINEL_USER_ID

QUESTION = {"messages": [{"role": "user", "content": "how am I doing?"}]}


def _default_cap(monkeypatch: pytest.MonkeyPatch, questions: int) -> None:
    """Set the DEPLOYMENT cap the way an operator does — the env."""
    monkeypatch.setenv("PREMIUM_COACH_QUESTIONS", str(questions))
    get_settings.cache_clear()


# ── the resolution, with no database ──────────────────────────────────────────


def test_no_owner_cap_takes_the_deployment_default(
    env: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _default_cap(monkeypatch, 5)
    assert gate.premium_allowance() == {gate.COACH: 5}
    assert gate.premium_allowance(None) == {gate.COACH: 5}


def test_an_unlimited_owner_on_a_capped_deployment_is_uncapped(
    env: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The operator's own case: guests at 20, the owner paying their own bill at none."""
    _default_cap(monkeypatch, 20)
    assert gate.premium_allowance(0) == {}


def test_a_capped_guest_on_an_unlimited_deployment_is_capped(
    env: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The other crossing. An override that could only narrow would pass the test above."""
    _default_cap(monkeypatch, 0)
    assert gate.premium_allowance(3) == {gate.COACH: 3}


def test_the_row_carries_its_cap_through_both_premium_paths(
    env: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A self-hosted unlock must not drop the cap — that is the path open signups take."""
    row = Subscription(
        status="active",
        plan="comp_12mo",
        trial_end=None,
        current_period_end=datetime.now(tz=UTC) + timedelta(days=30),
        coach_questions=7,
    )
    monkeypatch.setenv("SELF_HOST_UNLOCKED", "false")
    get_settings.cache_clear()
    assert evaluate(row).coach_questions == 7

    monkeypatch.setenv("SELF_HOST_UNLOCKED", "true")
    get_settings.cache_clear()
    assert evaluate(row).coach_questions == 7, "a self-hosted unlock dropped the owner's cap"
    assert evaluate(None).coach_questions is None, "an owner with no row was given a cap"


# ── the cap at the HTTP edge ──────────────────────────────────────────────────


@pytest.fixture
def owner_cap(db: None) -> Iterator[Callable[[int | None], None]]:  # noqa: ARG001
    """Set the seeded owner's own cap, and hand them back to the default afterwards.

    ``subscription`` survives the other seeds' truncates and ``entitle()`` never touches
    this column, so a cap left behind here would quietly cap every later test in the run.
    """

    def set_cap(value: int | None) -> None:
        with admin_connection() as conn, conn.cursor() as cur:
            cur.execute(
                "UPDATE subscription SET coach_questions = %s WHERE user_id = %s",
                (value, SENTINEL_USER_ID),
            )
            assert cur.rowcount == 1, "no subscription row — the cap landed nowhere"

    yield set_cap
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE subscription SET coach_questions = NULL WHERE user_id = %s",
            (SENTINEL_USER_ID,),
        )


@pytest.mark.integration
def test_an_owner_cap_below_the_default_refuses_at_their_number(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
    owner_cap: Callable[[int | None], None],
) -> None:
    _default_cap(monkeypatch, 5)
    owner_cap(1)
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
    refused = bed.post("/api/coach", json=QUESTION, headers=AUTH)
    assert refused.status_code == 402, "the owner's cap of 1 lost to the default of 5"
    assert refused.json()["detail"]["limit"] == 1


@pytest.mark.integration
def test_an_unlimited_owner_is_never_capped_under_a_capped_default(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
    owner_cap: Callable[[int | None], None],
) -> None:
    """The deployment this was built for: guests capped, the operator not."""
    _default_cap(monkeypatch, 1)
    owner_cap(0)
    for i in range(3):
        response = bed.post("/api/coach", json=QUESTION, headers=AUTH)
        assert response.status_code == 200, f"question {i + 1} was capped for an unlimited owner"


@pytest.mark.integration
def test_the_meter_reports_the_owner_cap_not_the_default(
    bed: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    owner_cap: Callable[[int | None], None],
) -> None:
    """The number shown must be the number enforced — for this owner, not the box."""
    _default_cap(monkeypatch, 20)
    owner_cap(3)
    included = bed.get("/api/entitlement", headers=AUTH).json()["included"]
    coach = [meter for meter in included if meter["feature"] == gate.COACH]
    assert len(coach) == 1
    assert coach[0]["limit"] == 3, "the meter showed the deployment's 20, not the owner's 3"

    owner_cap(0)
    included = bed.get("/api/entitlement", headers=AUTH).json()["included"]
    assert not [m for m in included if m["feature"] == gate.COACH], (
        "an unlimited owner was shown a meter"
    )
