"""The AI paywall at the HTTP edge — ``require_ai_access`` (Phase 6.6a, §12.3).

One dependency, used in place of ``CurrentUser`` on every premium endpoint. It
authenticates as before and then asks ``core.entitlement`` — the same function the nightly
chain asks — whether this owner may have AI output at all. If not: **402**, before the
handler body, before any model, before any stored AI row is read.

``MULTI_USER.md`` §12.7's invariant is *no AI response bytes ever leave the server for a
request whose owner is not premium — enforced at the endpoint AND in the jobs, from
server-owned entitlement, with RLS underneath.* This module is the endpoint half. Three
of its design choices are that invariant, restated as code:

* **It runs on the server route, not the screen.** A patched client, a curl, a replayed
  request — all reach the same dependency, and all get 402. The client renders what the
  server already decided; it is never asked.
* **It replaces ``CurrentUser`` rather than sitting beside it.** An endpoint cannot take
  the owner's identity without also taking the gate, so "someone added an AI route and
  forgot the dependency" needs a *deliberate* choice of the ungated alias — and
  ``tests/premium/test_ai_gate.py`` fails on any un-allowlisted mounted route with no gate.
* **402, not 403.** "Payment Required" is what this is, and the body says so in the shape
  the app renders a locked card from — ``{"locked": true, "feature": …, "upgrade": …}``.
  An error dialog for an unsubscribed user would be a lie about what happened.

## Free reads keep serving — with the AI fields OMITTED

``/api/today`` and ``/api/sleep/consistency`` are FREE endpoints that each carry one
LLM-authored field. They are not gated; :func:`strip_ai_fields` removes those fields from
the payload instead, so the page still renders every metric. §12.7 is explicit that the
field is *omitted*, not nulled and not hidden: "the data is not in the response at all, so
there's nothing to sniff." The ``locked`` marker that replaces it says which fields were
withheld, so the client can render the upsell without guessing.

## Two allowance tables, with OPPOSITE defaults

:data:`FREE_ALLOWANCE` prices a NON-premium owner and every entry is **0** — since
2026-08-02 the free tier has no AI surface at all. :data:`PREMIUM_ALLOWANCE` prices a
paying one and holds one entry: the coach, at :data:`PREMIUM_COACH_QUESTIONS` per rolling
:data:`PREMIUM_WINDOW_DAYS` local days. :mod:`healthee.core.allowance` is the ledger both
are checked against, and entitlement is asked FIRST, so only one ever applies to a request.

**The defaults are opposite, and that is the trap this paragraph exists to disarm.** A
feature absent from ``FREE_ALLOWANCE`` is **hard-locked** (fail closed — nobody paid); a
feature absent from ``PREMIUM_ALLOWANCE`` is **unlimited** (fail open — they did). Neither
table may be read with the other's assumption.

The charge happens in the dependency, not after the work, because that is the order that
cannot be raced: the ledger is edited under a row lock before the handler starts. What a
handler owes in return is a **refund** when it delivered nothing — :func:`refund_ai_use`,
"if this request charged a ledger, un-charge it". It stays a no-op for a request that
charged nothing, and is emphatically not one for a premium coach question any more: that
charges, so a refusal, an unvalidatable answer or a transport failure gives the slot back.
**We do not bill a slot for an answer we did not deliver.**

**The metering never runs on a read.** :func:`gate_free_payload` asks entitlement only, no
read path calls the coach, and nothing is generated for a free owner at all.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, HTTPException, Request

from healthee.core import allowance
from healthee.core.config import get_settings
from healthee.core.entitlement import entitlement_of, is_premium
from healthee.core.logging import get_logger
from healthee.core.request_auth import CurrentUser
from healthee.core.supabase_auth import RequestUser

log = get_logger(__name__)

# The premium features, as the 402 body names them — and the granularity both allowance
# tables are priced at, which is why the coach is separate from the cards.
COACH = "coach"
INSIGHT = "insight"
NOTABLE = "notable"
CHALLENGES = "challenges"
# The warmed read-surface coaching lines: `/api/today`'s `action` AND
# `/api/sleep/consistency`'s `tonight`. One feature because they are one generator
# (`insights.coaching.warm_lines`) and one entitlement; PRICING.md §1a names only the
# daily action, which is a gap in the doc rather than a second product.
DAILY_ACTION = "daily_action"

# Every feature this gate can refuse, in the order the app lists them on the upsell screen.
# `api.routers.entitlement` re-exports it, so a feature added here cannot go missing there.
FEATURES: tuple[str, ...] = (COACH, INSIGHT, NOTABLE, CHALLENGES, DAILY_ACTION)

# PRICING.md §1a's tier table for a NON-premium owner, as the only executable copy of it:
# how many times a free owner may use each feature per rolling `allowance.WINDOW_DAYS`.
#
# EVERY ENTRY IS ZERO — the free tier has no AI at all (owner decision, 2026-08-02,
# PRICING.md §0). What that replaced was a metered taste (1 coach question + 1 daily-action
# reveal per rolling 7 days) justified here at length as "bounded so cost is trivial".
# Measured, it was neither bounded nor a taste: **$0.81 per free owner per month, forever**,
# and at 5% conversion each payer carried ~19 of them — $15.39/month of giveaway against
# $3.12 of net revenue. A recurring free LLM call is a subscription given away, and no
# amount of prompt-shaving fixes a recurring giveaway. Selling the coach moves to the
# landing page.
#
# The dict and its ledger stay rather than being deleted, because §1a names them as "the
# executable table" and a zero is a real, readable price: re-granting a taste is then a
# NUMBER, not a rewrite. `AIGate._free` still spends the ledger for any entry made
# non-zero, and `_spent_body`'s free branch is the refusal that produces.
#
# A feature absent from this dict is hard-locked too (`.get(feature, 0)`) — failing closed
# is a paywall's only safe default, and the OPPOSITE of `PREMIUM_ALLOWANCE`'s.
FREE_ALLOWANCE: dict[str, int] = {
    COACH: 0,
    DAILY_ACTION: 0,
    INSIGHT: 0,
    NOTABLE: 0,
    CHALLENGES: 0,
}

# What ONE PREMIUM SUBSCRIPTION INCLUDES per rolling window — PRICING.md §0's decided cap,
# and the only executable copy of that number.
#
# 20, because a coach question costs **$0.179** measured from provider billing (§3.1) and
# #105 — the plan to make it cheaper by not re-sending the corpus every round — was run and
# saved nothing (−2.9%, sign not established, two fewer answers out of fourteen). At 30
# that is $6.98 of cost against $6.99 of price: −8% monthly, −26% annual, at full use. At
# 20 it runs +25% monthly and +7% annual at full use, and is still a question every day and
# a half. The measured, unspent lever that could buy 30 back at the same price is
# `DEFAULT_TOP_N` 6 → 4 (−18.8% input tokens, sign established, ship rate flat).
#
# **Only the coach is here, and a feature ABSENT from this table is UNLIMITED** — the
# opposite of `FREE_ALLOWANCE`, where absent means hard-locked. The cards are uncapped on
# purpose and priced, not forgotten: $0.0084 a card, and a fixed $1.27/owner/month for the
# nightly chain, both inside the price. A 0 here would hard-lock a paying owner.
PREMIUM_COACH_QUESTIONS = 20


def premium_allowance(coach_questions: int | None = None) -> dict[str, int]:
    """What a PREMIUM owner gets, per feature, per rolling window.

    A function, not a constant: the coach cap is deployment config, and
    `core.config.premium_coach_questions` carries the argument for why. **0 means
    unlimited and is expressed by ABSENCE**, the way this module already expresses
    it — a `0` left in the mapping would read as "capped at zero", which is the
    exact confusion `AIGate` warns about at its `.get`.

    ``coach_questions`` is ONE owner's cap from their row (0022). None defers to the
    deployment; anything else replaces it in either direction, so a deployment capped at
    20 can leave its operator unlimited and an unlimited one can cap a guest. Passed in,
    not read here, so the gate and the meter use the row they already hold.
    """
    default = get_settings().premium_coach_questions
    capped = default if coach_questions is None else coach_questions
    return {COACH: capped} if capped > 0 else {}


# The cap's window: rolling THIRTY LOCAL days in the owner's zone, not a calendar month.
# It reuses `core.allowance`, already locked, tested and timezone-correct, so the cap is a
# parameter rather than a second ledger to get wrong; a calendar month would let an owner
# spend 20 on the 31st and 20 more on the 1st; and PRICING.md §3.1's cost model is
# per-30-days, so this is the window the price was computed over.
PREMIUM_WINDOW_DAYS = 30

# Where a charged request records that it charged, as `(feature, window_days)` — the pair
# the refund needs to reach the same `kv` row. On `request.state`, per request and dying
# with it: re-reading entitlement and the ledger in the refund path would be two more
# queries to rediscover what this process knew, and would guess wrong for a subscription
# that changed mid-request.
_CHARGED_ATTR = "healthee_allowance_charged"

# `/api/today` and `/api/sleep/consistency` are free endpoints carrying one AI field
# each. Named here, next to the gate, because the omission and the 402 are one policy.

# The key the stripped payload carries instead. Its presence IS the signal — a premium
# payload has no `locked` key at all, so the shapes differ without inspecting values.
LOCKED_KEY = "locked"


def locked_body(feature: str) -> dict:
    """The HARD-LOCK body — the AI layer is the paid tier and the way in is to pay.

    Same shape in the 402 and in a stripped payload. It carries the ``upgrade`` URL and
    says nothing about waiting, because nothing here reopens on its own.
    """
    return {
        LOCKED_KEY: True,
        "feature": feature,
        "upgrade": get_settings().upgrade_url,
        "error": (
            "the AI layer is the premium tier — your metrics, charts, baselines and "
            "findings stay free and complete"
        ),
    }


def _spent_body(
    feature: str, verdict: allowance.Verdict, *, window_days: int, premium: bool
) -> dict:
    """The body for a window that WILL reopen, carrying the instant it reopens.

    Two sentences, because two different people read this and only one is being sold
    anything. A **premium** owner has spent what they already paid for: no upsell and no
    ``upgrade`` URL, because there is nothing here to buy and pitching a subscription at a
    subscriber is a lie about what happened. A **free** owner with a re-granted taste has
    spent a sample, and for them the upgrade really is the answer.

    That branch survives a table of zeros deliberately, because of what §1a promises about
    the table: re-granting a taste must be a *number*, and a number-only change that fell
    back to the hard-lock body would tell somebody who need only wait until Tuesday that
    they must subscribe. Kept and tested against a patched table, not deleted.
    """
    body = {
        LOCKED_KEY: True,
        "feature": feature,
        "limit": verdict.limit,
        "used": verdict.used,
        "resets_at": verdict.resets_at.isoformat(),
        "retry_after_s": verdict.retry_after_s,
    }
    if premium:
        return body | {
            "error": (
                f"your subscription includes {verdict.limit} of these per {window_days} days "
                f"and you have used them — the next one opens on "
                f"{verdict.resets_at.date().isoformat()}. Nothing else in premium is capped."
            )
        }
    return body | {
        "upgrade": get_settings().upgrade_url,
        "error": (
            f"you have used the free tier's {verdict.limit} per {window_days} days for this "
            f"— it comes back on its own, and premium's allowance is far larger"
        ),
    }


class AIGate:
    """A FastAPI dependency that authenticates, then refuses 402 if not entitled.

    A class rather than a closure so the feature is a readable attribute: the route
    completeness test walks every mounted route's dependency tree looking for one of these,
    and ``isinstance`` cannot be fooled by a same-named function defined somewhere else.
    """

    def __init__(self, feature: str) -> None:
        self.feature = feature

    def __call__(self, request: Request, user: CurrentUser) -> RequestUser:
        """Return the authenticated owner, or raise 402 — ``require_ai_access`` (§12.3).

        Entitlement first, always: it is what keeps the two tables from ever both
        applying to one request.
        """
        current = entitlement_of(user.id)
        if current.premium:
            return self._premium(request, user, current.coach_questions)
        return self._free(request, user)

    def _premium(
        self, request: Request, user: RequestUser, coach_questions: int | None = None
    ) -> RequestUser:
        """A paying owner: straight through, unless this feature carries an included cap.

        ``.get`` returning ``None`` means UNLIMITED, so this reads it with ``is None`` and
        not a falsy check — which would turn "not capped" into "capped at zero".
        """
        limit = premium_allowance(coach_questions).get(self.feature)
        if limit is None:
            return user
        verdict = allowance.spend(
            user.id, user.timezone, self.feature, limit, window_days=PREMIUM_WINDOW_DAYS
        )
        if not verdict.allowed:
            log.info("402 %s for %s — the included %d are spent", self.feature, user.id, limit)
            # Still 402, not 429: the app renders a locked card from `locked: true` on a
            # 402 and this IS that card — a stated product limit with a reopening date,
            # not a failure a 429 would surface as an error dialog.
            raise HTTPException(
                status_code=402,
                detail=_spent_body(
                    self.feature, verdict, window_days=PREMIUM_WINDOW_DAYS, premium=True
                ),
                headers={"Retry-After": str(max(1, verdict.retry_after_s))},
            )
        setattr(request.state, _CHARGED_ATTR, (self.feature, PREMIUM_WINDOW_DAYS))
        return user

    def _free(self, request: Request, user: RequestUser) -> RequestUser:
        """A non-premium owner: refused, unless somebody prices this feature non-zero.

        Every entry is zero today, so this hard-locks every feature; the spend path below
        is what makes re-granting a taste a number rather than a rewrite.
        """
        limit = FREE_ALLOWANCE.get(self.feature, 0)
        if limit <= 0:
            log.info("402 %s for %s — not premium, no free allowance", self.feature, user.id)
            raise HTTPException(status_code=402, detail=locked_body(self.feature))
        verdict = allowance.spend(user.id, user.timezone, self.feature, limit)
        if not verdict.allowed:
            log.info("402 %s for %s — free allowance spent", self.feature, user.id)
            raise HTTPException(
                status_code=402,
                detail=_spent_body(
                    self.feature, verdict, window_days=allowance.WINDOW_DAYS, premium=False
                ),
                headers={"Retry-After": str(max(1, verdict.retry_after_s))},
            )
        setattr(request.state, _CHARGED_ATTR, (self.feature, allowance.WINDOW_DAYS))
        return user


def refund_ai_use(request: Request, user: RequestUser) -> None:
    """Un-charge this request's allowance use, if it made one and delivered nothing.

    Called by a handler that produced no value — a refusal decided before the model, a
    transport failure, the honest fallback, or an answer served from a cache this request
    did not fill. **We do not bill a slot for an answer we did not deliver**, and since the
    premium coach cap landed that has teeth: it used to be a no-op for every premium
    request and is now what keeps a paying owner's 20 honest.

    Idempotent, and still a no-op for a request that charged nothing (an uncapped premium
    feature; anything free): the marker is only set by a request that wrote to the ledger,
    and it is cleared here so a second call (a handler that refunds in both a branch and
    its ``except``) cannot mint a second use back. It carries the WINDOW as well as the
    feature, because the refund has to reach the same ``kv`` row.
    """
    charged = getattr(request.state, _CHARGED_ATTR, None)
    if charged is None:
        return
    setattr(request.state, _CHARGED_ATTR, None)
    feature, window_days = charged
    log.info("refunding the %s use for %s — the request delivered nothing", feature, user.id)
    allowance.refund(user.id, user.timezone, feature, window_days=window_days)


def locked_features(user: RequestUser) -> list[str]:
    """Which features this owner may not use *because they have not paid* — the upsell list.

    It is the UPGRADEABLE list, which is why a premium owner's stays empty even when their
    coach cap is spent: a capped subscriber is not being sold anything, and putting
    ``coach`` in a list the app renders as upgrade cards would pitch a subscription at a
    subscriber. Their limit travels on the 402 instead (:func:`_spent_body`), with the day
    it reopens.

    Reporting only: it :func:`~healthee.core.allowance.peek`\\ s rather than spending, so
    polling can never cost somebody a question. A metered free feature with a slot free is
    deliberately absent — what ``EntitlementResponse.locked`` being a LIST was built for.
    """
    if is_premium(user.id):
        return []
    return [
        feature
        for feature in FEATURES
        if not _has_free_use(user, feature, FREE_ALLOWANCE.get(feature, 0))
    ]


def _has_free_use(user: RequestUser, feature: str, limit: int) -> bool:
    """Whether a non-premium ``user`` has an unspent allowance for ``feature``."""
    if limit <= 0:
        return False
    return allowance.peek(user.id, user.timezone, feature, limit).allowed


# The gated identities, one per feature. An endpoint takes ONE of these in place of
# `CurrentUser`; taking `CurrentUser` on an AI route is what the completeness test fails.
CoachUser = Annotated[RequestUser, Depends(AIGate(COACH))]
InsightUser = Annotated[RequestUser, Depends(AIGate(INSIGHT))]
NotableUser = Annotated[RequestUser, Depends(AIGate(NOTABLE))]
ChallengeUser = Annotated[RequestUser, Depends(AIGate(CHALLENGES))]
DailyActionUser = Annotated[RequestUser, Depends(AIGate(DAILY_ACTION))]

__all__ = [
    "CHALLENGES",
    "COACH",
    "DAILY_ACTION",
    "FEATURES",
    "FREE_ALLOWANCE",
    "INSIGHT",
    "LOCKED_KEY",
    "locked_body",
    "NOTABLE",
    "premium_allowance",
    "PREMIUM_COACH_QUESTIONS",
    "PREMIUM_WINDOW_DAYS",
    "AIGate",
    "ChallengeUser",
    "CoachUser",
    "DailyActionUser",
    "InsightUser",
    "NotableUser",
    "locked_features",
    "refund_ai_use",
]
