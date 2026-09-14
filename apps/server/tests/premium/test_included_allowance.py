"""``GET /api/entitlement``'s ``included`` — a subscriber's own balance, before it refuses.

#116. ``PRICING.md`` §0 sells "20 coach questions per rolling 30 days" and argues that a
stated number beats "unlimited (fair-use)" because *"'unlimited' with a silent throttle is
the dishonest version of the same thing"*. Until this field the only way to learn the
balance was to be refused — a stated limit nobody can observe until it stops them.

The assertions that matter most, in order:

* **reading the balance does not spend it** — the failure mode is silent and bills the
  owner, so this hammers the endpoint and reads the raw ledger row back;
* **the number tracks ``gate.PREMIUM_ALLOWANCE``**, not a literal 20 — two copies of a
  priced promise is a customer told the wrong number;
* **an uncapped premium feature is absent, not zero** — ``gate``'s tables have opposite
  defaults and a meter reading empty is the exact inversion of "they paid, so it's
  unlimited";
* **a free owner is shown no meter at all** — "0 of 20 remaining" to somebody who was
  never sold 20 is an upsell wearing a meter's clothes.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime

import pytest
from fastapi.testclient import TestClient
from tests.insights._stub import StubLLM
from tests.premium.conftest import AUTH

from healthee.api import gate
from healthee.core import allowance
from healthee.core.config import get_settings
from healthee.core.db import tenant_transaction
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID

pytestmark = pytest.mark.integration

QUESTION = {"messages": [{"role": "user", "content": "how am I doing?"}]}


def _included(bed: TestClient) -> list[dict]:
    """The whole ``included`` list, over real HTTP."""
    response = bed.get("/api/entitlement", headers=AUTH)
    assert response.status_code == 200, response.text
    return response.json()["included"]


def _coach_meter(bed: TestClient) -> dict:
    meters = [entry for entry in _included(bed) if entry["feature"] == gate.COACH]
    assert len(meters) == 1, f"expected exactly one coach meter, got {meters}"
    return meters[0]


def _ledger_rows() -> dict[str, str]:
    """The RAW allowance rows — a measure of the ledger that does not go through peek.

    ``{key: value}``, the value being the encoded list of use instants. Comparing this
    before and after is what proves "the ledger did not move": a peek that quietly
    recorded would change the value even where the reported count happened to agree.
    """
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute(
            "SELECT key, value FROM kv WHERE user_id = %s AND key LIKE 'allowance%%'",
            (SENTINEL_USER_ID,),
        )
        return {row[0]: row[1] for row in cur.fetchall()}


def _cap_at(monkeypatch: pytest.MonkeyPatch, questions: int) -> None:
    """Set the coach cap the way a DEPLOYMENT does — the env, not the mapping.

    `gate.premium_allowance()` reads `core.config`, so patching a dict no longer
    changes anything. Going through the env is also the stronger test: it
    exercises the path an operator actually uses, including the settings cache.
    """
    monkeypatch.setenv("PREMIUM_COACH_QUESTIONS", str(questions))
    get_settings.cache_clear()


# ── the one that bills the owner if it breaks ─────────────────────────────────


def test_reading_the_balance_never_spends_one(bed: TestClient, stub: StubLLM) -> None:
    """PEEK, never SPEND. An app polling its own meter must not consume the thing it meters.

    Hammered rather than called once because the failure is *silent*: a `spend` here would
    still return a plausible-looking payload, and the owner would simply find their twenty
    questions gone. The ledger is read raw, before and after, so both the count and the
    stored instants have to be unchanged.
    """
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
    assert stub.calls > 0, "premise: a question was actually asked"
    before = _ledger_rows()
    assert before, "premise: the ledger has a row to be moved"

    for _ in range(25):
        meter = _coach_meter(bed)
        assert meter["used"] == 1, "polling the meter moved the meter"

    assert _ledger_rows() == before, "reading the balance wrote to the allowance ledger"
    assert _coach_meter(bed)["remaining"] == gate.PREMIUM_COACH_QUESTIONS - 1


def test_reading_it_on_an_untouched_ledger_creates_no_row_at_all(bed: TestClient) -> None:
    """``peek`` reads; it does not claim the row ``spend`` inserts before locking it."""
    for _ in range(5):
        assert _coach_meter(bed)["used"] == 0
    assert _ledger_rows() == {}, "peeking an unused allowance created a ledger row"


# ── the count itself ──────────────────────────────────────────────────────────


def test_a_premium_owner_sees_the_real_remaining_count_and_it_decrements(
    bed: TestClient, stub: StubLLM
) -> None:
    """The whole point of the field: twenty, then nineteen, then eighteen."""
    opening = _coach_meter(bed)
    assert opening["limit"] == gate.PREMIUM_COACH_QUESTIONS
    assert opening["used"] == 0
    assert opening["remaining"] == gate.PREMIUM_COACH_QUESTIONS
    assert opening["window_days"] == gate.PREMIUM_WINDOW_DAYS

    for asked in (1, 2):
        assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
        meter = _coach_meter(bed)
        assert meter["used"] == asked
        assert meter["remaining"] == gate.PREMIUM_COACH_QUESTIONS - asked
    assert stub.calls > 0


def test_a_meter_with_slots_free_names_no_reset_because_nothing_is_being_waited_for(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
) -> None:
    """A reset instant beside "19 remaining" reads as a countdown that is not running."""
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
    meter = _coach_meter(bed)
    assert meter["remaining"] > 0
    assert meter["resets_at"] is None
    assert meter["retry_after_s"] is None


def test_at_the_cap_it_reads_zero_and_names_the_instant_it_reopens(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """ "You have 0 left" without "and it comes back on the 14th" is the vague half (§Errors).

    The same two values the 402 carries, on the surface an owner can reach *before* the
    402 — an absolute instant a cached payload survives, and relative seconds a wrong
    device clock survives.
    """
    _cap_at(monkeypatch, 1)
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 402, (
        "premise: the cap is actually spent"
    )

    meter = _coach_meter(bed)
    assert meter["limit"] == 1
    assert meter["used"] == 1
    assert meter["remaining"] == 0
    assert meter["resets_at"], "a spent meter that cannot say when is the vague refusal"
    assert datetime.fromisoformat(meter["resets_at"]) > datetime.now().astimezone()
    assert meter["retry_after_s"] > 0


def test_the_meter_and_the_402_tell_the_same_story(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Two surfaces, one ledger. A meter that disagreed with the refusal would be worse
    than no meter — the owner would be told two numbers and have to guess which is real."""
    _cap_at(monkeypatch, 2)
    for _ in range(2):
        assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200
    refused = bed.post("/api/coach", json=QUESTION, headers=AUTH)
    assert refused.status_code == 402

    detail = refused.json()["detail"]
    meter = _coach_meter(bed)
    assert (meter["limit"], meter["used"]) == (detail["limit"], detail["used"])
    assert meter["resets_at"] == detail["resets_at"]


# ── single-sourced from the table, not restated ───────────────────────────────


def test_the_reported_cap_tracks_the_table_and_is_not_a_literal(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``PREMIUM_ALLOWANCE`` stays the only executable copy of the priced number.

    Change the table and the wire must follow. A response that restated ``20`` would be a
    second definition of a promise §0 sells, and the cost of two definitions of a priced
    number is a customer told the wrong one.
    """
    _cap_at(monkeypatch, 7)
    meter = _coach_meter(bed)
    assert meter["limit"] == 7, "the endpoint is reporting a number of its own"
    assert meter["remaining"] == 7


def test_a_feature_capped_later_appears_without_anyone_editing_the_endpoint(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Driven off the TABLE, not off a hardcoded ``coach``.

    The next cap somebody adds is priced in one place; if this endpoint had to be edited
    too, the day it was forgotten a paying owner would hit a limit that no surface admits
    exists.
    """
    monkeypatch.setattr(
        gate, "premium_allowance", lambda _coach_questions=None: {gate.COACH: 20, gate.NOTABLE: 3}
    )
    by_feature = {entry["feature"]: entry for entry in _included(bed)}
    assert set(by_feature) == {gate.COACH, gate.NOTABLE}
    assert by_feature[gate.NOTABLE]["limit"] == 3
    assert by_feature[gate.NOTABLE]["remaining"] == 3
    assert by_feature[gate.NOTABLE]["window_days"] == gate.PREMIUM_WINDOW_DAYS


def test_an_uncapped_premium_feature_is_absent_and_never_reported_at_zero(
    bed: TestClient,
) -> None:
    """``gate``'s asymmetry, on the wire: absent from ``PREMIUM_ALLOWANCE`` is UNLIMITED.

    An entry with ``limit: 0`` for the insight cards would render as a meter reading
    empty — the exact inversion of the truth, and the shape a reader who brought
    ``FREE_ALLOWANCE``'s fail-closed default would produce.
    """
    included = _included(bed)
    assert {entry["feature"] for entry in included} == {gate.COACH}
    for uncapped in (gate.INSIGHT, gate.NOTABLE, gate.CHALLENGES, gate.DAILY_ACTION):
        assert uncapped not in {entry["feature"] for entry in included}
    assert all(entry["limit"] > 0 for entry in included), "a meter shipped capped at zero"


def test_the_balance_is_read_from_the_thirty_day_row_not_the_seven_day_one(
    bed: TestClient,
) -> None:
    """The window is in the ledger key, so reading the default would report the wrong row.

    A use recorded under the free tier's 7-day window is not one of the paid twenty, and a
    meter that counted it would tell a subscriber they had spent a question they never did.
    """
    for _ in range(3):
        allowance.spend(SENTINEL_USER_ID, SENTINEL_TZ, gate.COACH, 5)  # the 7-day window
    assert f"allowance:{gate.COACH}:{allowance.WINDOW_DAYS}d" in _ledger_rows(), "premise"
    assert _coach_meter(bed)["used"] == 0, "the free window's uses were billed as paid ones"

    allowance.spend(
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        gate.COACH,
        gate.PREMIUM_COACH_QUESTIONS,
        window_days=gate.PREMIUM_WINDOW_DAYS,
    )
    assert _coach_meter(bed)["used"] == 1


# ── the free tier is shown no meter at all ────────────────────────────────────


def test_a_free_owner_is_shown_no_cap_they_were_never_sold(
    bed: TestClient, make_free: Callable[[], None]
) -> None:
    """ "0 of 20 remaining" to somebody with no access is an upsell wearing a meter.

    Their surface is ``locked``, which is the upgradeable list and is exactly what a free
    owner needs; ``included`` is the balance on something already bought, and they bought
    nothing. This is also the guard on ``included_allowances``' entitlement check: drop it
    and a free owner is told they have twenty questions in hand.
    """
    make_free()
    body = bed.get("/api/entitlement", headers=AUTH).json()
    assert body["premium"] is False
    assert body["included"] == []
    assert set(body["locked"]) == set(gate.FEATURES), "the upsell surface still does its job"


def test_a_capped_subscriber_is_metered_but_still_sold_nothing(
    bed: TestClient,
    stub: StubLLM,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The seam between the two lists, at the one moment they could be confused.

    A subscriber at their cap has a meter reading zero AND an empty upgrade list. Putting
    ``coach`` in ``locked`` here would render an upgrade card at somebody who already
    subscribed — which is why the count needed its own home rather than a widened
    ``locked``.
    """
    _cap_at(monkeypatch, 1)
    assert bed.post("/api/coach", json=QUESTION, headers=AUTH).status_code == 200

    body = bed.get("/api/entitlement", headers=AUTH).json()
    assert body["premium"] is True
    assert body["locked"] == [], "a paying owner was shown something to upgrade to"
    assert [entry["remaining"] for entry in body["included"]] == [0]
