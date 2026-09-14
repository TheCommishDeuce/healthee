"""What a subscription INCLUDES and how much of it is left — the meter, not the paywall.

The reporting half of :mod:`healthee.api.gate`. The gate spends the ledger and refuses;
this reads the same ledger and tells the owner where they stand *before* it refuses them.

## Why this exists at all (#116)

``PRICING.md`` §0 sells "20 coach questions per rolling 30 days" and argues, in its own
words, that *"a stated number beats 'unlimited (fair-use)'"* because *"'unlimited' with a
silent throttle is the dishonest version of the same thing"*. Until this module the number
was stated in the pricing page and enforced in the gate, and an owner could learn their
own balance in exactly one way: by being refused. **A stated limit nobody can observe
until it stops them is most of the way back to the thing that argument rejected.**

## Why it is not ``locked``

``gate.locked_features`` is the **upgradeable** list, and it is empty for a capped
premium owner on purpose — putting ``coach`` in a list the app renders as upgrade cards
would pitch a subscription at a subscriber. So the count needed its own home rather than
a widened meaning for a field that already has one. Read the two together: ``locked``
answers *"what would paying get me"*, ``included`` answers *"what did paying get me, and
how much of it is left"*.

## Three shapes, and what each one must not be mistaken for

* **A capped feature** emits one entry: ``limit``/``used``/``remaining``, the window it
  is counted over, and — once spent — when it reopens.
* **An uncapped premium feature emits NO entry.** ``gate`` documents the asymmetry a
  reader has to hold: absent from ``FREE_ALLOWANCE`` means hard-locked, absent from
  ``PREMIUM_ALLOWANCE`` means **unlimited**. An entry with ``limit: 0`` for the insight
  cards would render as a meter reading empty — the exact inversion of "they paid, so
  this is uncapped". Nothing to meter, nothing emitted.
* **A free owner gets an empty list**, never a row of zeros. They were not sold twenty of
  anything, and "0 of 20 remaining" on a payload for somebody who has no access at all is
  an upsell disguised as a meter. Selling them the tier is ``locked``'s job.

## Two properties that are load-bearing rather than incidental

* **It PEEKs.** Reading your own balance must never consume it — the failure mode is
  silent and bills the owner, so ``tests/premium/test_included_allowance.py`` hammers the
  endpoint and asserts the ledger did not move.
* **The cap is read from the table, never restated.** The list is built by iterating
  ``gate.PREMIUM_ALLOWANCE`` itself, so a feature capped later appears here without
  anybody remembering this file exists, and the number shown is the number enforced. A
  literal ``20`` here would be a second definition of a priced promise, and the cost of
  two definitions is a customer told the wrong number.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict

from healthee.api import gate
from healthee.core import allowance
from healthee.core.entitlement import entitlement_of
from healthee.core.supabase_auth import RequestUser


class IncludedAllowance(BaseModel):
    """One capped feature's meter, as ``GET /api/entitlement`` reports it.

    ``remaining`` is ``limit - used``, floored at zero, and is carried rather than left
    to the client to subtract: it is the number the owner is actually asking for, and a
    client computing it is a client that can compute it differently from the gate.

    ``resets_at`` and ``retry_after_s`` are **null while any slot is free**, because
    nothing is being waited for and a reset instant beside "17 remaining" would read as a
    countdown that isn't running. Once the window is full they carry the same two values
    the 402 does (``gate._spent_body``), so a client can render one widget from either
    surface: the absolute instant survives being cached, the relative seconds survive a
    wrong device clock.
    """

    model_config = ConfigDict(extra="forbid")

    feature: str
    limit: int
    used: int
    remaining: int
    window_days: int
    resets_at: datetime | None
    retry_after_s: int | None


def included_allowances(user: RequestUser) -> list[IncludedAllowance]:
    """Every capped feature this owner's subscription includes, with the balance left.

    Empty for a non-premium owner — they hold no allowance to report, and their upsell
    travels on ``locked``. Empty as well for a premium owner while nothing is capped,
    which is the honest reading of an empty ``PREMIUM_ALLOWANCE``: unlimited everywhere.
    """
    current = entitlement_of(user.id)
    if not current.premium:
        return []
    # The owner's own cap from the row just read, so the meter shows the number the gate
    # enforces for THIS owner and not the deployment default.
    allowed = gate.premium_allowance(current.coach_questions)
    return [_meter(user, feature, limit) for feature, limit in allowed.items()]


def _meter(user: RequestUser, feature: str, limit: int) -> IncludedAllowance:
    """Read one feature's rolling window WITHOUT recording anything (``allowance.peek``).

    The window is ``gate.PREMIUM_WINDOW_DAYS``, passed explicitly for the reason the
    ledger keeps it in the key: the same recorded instants mean different things under a
    7-day and a 30-day count, so reading the default window would report a paying owner's
    balance out of a row the gate never writes.
    """
    verdict = allowance.peek(
        user.id, user.timezone, feature, limit, window_days=gate.PREMIUM_WINDOW_DAYS
    )
    spent = not verdict.allowed
    return IncludedAllowance(
        feature=feature,
        limit=verdict.limit,
        used=verdict.used,
        remaining=max(0, verdict.limit - verdict.used),
        window_days=gate.PREMIUM_WINDOW_DAYS,
        resets_at=verdict.resets_at if spent else None,
        retry_after_s=verdict.retry_after_s if spent else None,
    )


__all__ = ["IncludedAllowance", "included_allowances"]
