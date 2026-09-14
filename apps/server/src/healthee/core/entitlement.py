"""Is this owner entitled to the AI layer? — the ONE answer (Phase 6.6a, §12.2).

Everything that gates a premium surface — the FastAPI dependency in ``api.gate``,
``/api/today``'s field omission, and the nightly chain's skip — asks this module and
nothing else. That is the whole design: ``MULTI_USER.md`` §12.7's invariant is that no
AI response bytes leave the server for an unentitled owner, *enforced at the endpoint
AND in the jobs, from server-owned state*, and an invariant with two implementations is
an invariant with one bug waiting.

## Where the answer comes from, and where it does NOT

**From the ``subscription`` table, read per request.** Never a JWT claim, never a
request field, never a cached boolean that outlives a refund (§12.7: "forged/stolen JWT
claiming premium" and "keep access after cancel/refund/chargeback" are two separate
loopholes and this closes both — a forged token still resolves to a row that says
``none``, and every check re-reads the row).

The app role holds **SELECT and nothing else** on that table
(``db.provision_app_role``), so a request path cannot write entitlement even if
somebody later adds SQL that tries. The gate is enforced in code and *underwritten* by
a grant.

## The rule, stated exactly (§12.2 is ambiguous; this is the reading)

§12.2 writes it as ``status IN ('trialing','active')`` OR (``past_due`` within a grace
window) AND ``current_period_end > now()``. Read with Python's precedence that says a
``past_due`` row must ALSO be inside its ``current_period_end`` — which is
unsatisfiable, because a row only becomes ``past_due`` when the period it was paid for
has run out. So the AND distributes over both arms and the deadline moves with the
status:

* ``active``   → premium while ``now < current_period_end``;
* ``trialing`` → premium while ``now < trial_end`` (falling back to
  ``current_period_end`` when a provider only sets that one);
* ``past_due`` → premium while ``now < deadline + GRACE_DAYS`` — the dunning window
  (§12.5), so one failed renewal does not instantly wall a paying user out;
* ``canceled`` / ``expired`` / ``none`` / no row at all → **not** premium.

``canceled`` losing access immediately is a decision, not an oversight. The usual SaaS
behaviour ("cancelled, keep it until the period ends") is real, but expressing it here
would mean this module deciding what a provider's word means — and this module is the
one place that must be dumb and literal. A provider that reports "cancels at period
end" is mapped by the webhook layer (6.6b) to a row that is still ``active`` with the
final ``current_period_end``; ``canceled`` here means access ends now.

A row with **no deadline at all** is not premium, whatever its status says. That is the
"granted once, forgotten" loophole, and failing closed is the only safe reading — an
entitlement nobody can date is one nobody can revoke.

## The self-hosted escape hatch

``SELF_HOST_UNLOCKED`` (default **false**) entitles every owner on the deployment. It
exists because the paywall's whole reason for being is *our* LLM bill on *our* hosted
service (``PRICING.md`` §6.1), and that argument evaporates on a box somebody else
owns, running their own OpenRouter key, which is the product's stated brand ("self-host
it and own it"). The code cannot tell a self-hosted deploy from the hosted one, so the
operator declares it — server-owned config, not a client claim, and exactly the
"admin/config flag" §12.6 step (a) prescribes.

It is **not** the sentinel-is-premium shortcut, which was considered and rejected:
see ``docs/MULTI_USER.md`` §12.6a for that argument. It is announced at startup
(``api.app``, ``jobs.scheduler``) so a hosted deploy that sets it by accident says so
in the log on every boot rather than quietly giving the AI layer away.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from healthee.core.config import get_settings
from healthee.core.db import tenant_transaction
from healthee.core.logging import get_logger

log = get_logger(__name__)

# The dunning window on `past_due` (§12.5): how long a failed renewal keeps working
# before the hard lock. A week is the shortest window that survives a card expiring
# over a weekend plus a provider's own retry schedule, and short enough that a
# genuinely lapsed subscription is not a month of free inference.
GRACE_DAYS = 7

# Statuses that mean "paying, or as good as" — each still bounded by its deadline.
_LIVE_STATUSES = frozenset({"active", "trialing"})

# The status that gets the grace window instead of a hard deadline.
_DUNNING_STATUS = "past_due"

# What `entitlement_of` reports when the owner has no row at all. A missing row and an
# explicit `none` are the same entitlement and are deliberately not distinguished here:
# both mean nobody has ever paid, and inventing a third state would give a caller
# something to branch on that has no consequence.
NO_SUBSCRIPTION = "none"

# Why an owner is premium. Carried on the wire (`/api/entitlement`) because "you have
# access" and "this whole box is unlocked" are different facts about a deployment, and
# an operator debugging a live install should not have to guess which one they are in.
SOURCE_SUBSCRIPTION = "subscription"
SOURCE_SELF_HOST = "self_host"
SOURCE_NONE = "none"

_READ_SQL = (
    "SELECT status, plan, trial_end, current_period_end, coach_questions "
    "FROM subscription WHERE user_id = %s"
)


@dataclass(frozen=True)
class Subscription:
    """The stored entitlement row, reduced to the fields the rule and the coach cap read."""

    status: str
    plan: str | None
    trial_end: datetime | None
    current_period_end: datetime | None
    # This owner's coach cap: None defers to the deployment's PREMIUM_COACH_QUESTIONS,
    # 0 is unlimited, N is N per rolling window (0022). Defaulted, so a row built by
    # hand for the status matrix does not have to say anything about the coach.
    coach_questions: int | None = None


@dataclass(frozen=True)
class Entitlement:
    """One owner's premium state at one instant — the answer every gate acts on.

    ``expires_at`` travels with ``premium`` because a client that can say *when* access
    ends can renew before it does; a bare boolean can only report the surprise
    afterwards.
    """

    premium: bool
    status: str
    source: str
    plan: str | None
    expires_at: datetime | None
    # The owner's own cap, carried to the gate and the meter so both take it from the
    # ONE row read that decided `premium`, rather than asking the table a second time.
    coach_questions: int | None = None


def evaluate(row: Subscription | None, now: datetime | None = None) -> Entitlement:
    """Decide entitlement from a stored row — pure, so the status matrix is testable.

    ``now`` is injectable for exactly that reason: the grace window and the expiry are
    the two things most likely to be got wrong, and a rule that can only be exercised
    by waiting a week is a rule nobody exercises.
    """
    now = now or datetime.now(tz=UTC)
    if _self_host_unlocked():
        return Entitlement(
            premium=True,
            status=row.status if row else NO_SUBSCRIPTION,
            source=SOURCE_SELF_HOST,
            plan=row.plan if row else None,
            expires_at=None,  # a self-hosted unlock has no term — there is nothing to renew
            coach_questions=row.coach_questions if row else None,
        )
    if row is None:
        return Entitlement(False, NO_SUBSCRIPTION, SOURCE_NONE, None, None)
    deadline = _deadline(row)
    premium = deadline is not None and now < deadline
    return Entitlement(
        premium=premium,
        status=row.status,
        source=SOURCE_SUBSCRIPTION if premium else SOURCE_NONE,
        plan=row.plan,
        expires_at=deadline,
        coach_questions=row.coach_questions,
    )


def _deadline(row: Subscription) -> datetime | None:
    """The instant this row stops being premium, or None when it never was.

    ONE definition (CLAUDE.md: one canonical definition per metric) — the status picks
    which stored instant bounds it and whether the dunning window is added, and nothing
    else in the codebase computes an expiry.
    """
    if row.status in _LIVE_STATUSES:
        end = row.trial_end if row.status == "trialing" and row.trial_end else None
        return end or row.current_period_end
    if row.status == _DUNNING_STATUS:
        end = row.current_period_end or row.trial_end
        return end + timedelta(days=GRACE_DAYS) if end else None
    return None


def _self_host_unlocked() -> bool:
    """Whether this whole deployment declares itself somebody's own box (see the header)."""
    return get_settings().self_host_unlocked


def warn_if_self_host_unlocked() -> None:
    """Say so on every boot when this deployment gives the AI layer away for free.

    Called by BOTH entry points (``api.app``'s lifespan and ``jobs.scheduler``'s main),
    because the flag changes what each of them does and an operator reads one log or the
    other. Same shape as ``core.db``'s app-role fallback warning: a state that is
    legitimate but consequential has to announce itself, or "we meant to turn that off"
    becomes something nobody can see.
    """
    if _self_host_unlocked():
        log.warning(
            "SELF_HOST_UNLOCKED is set — EVERY owner on this deployment is premium "
            "regardless of their subscription row. Correct for a self-hosted install; "
            "on the hosted service this is the paywall switched off."
        )


def read_subscription(user_id: UUID) -> Subscription | None:
    """``user_id``'s stored row, or None. Owner-scoped read (RLS underneath, §3.3)."""
    with tenant_transaction(user_id) as cur:
        cur.execute(_READ_SQL, (user_id,))
        row = cur.fetchone()
    if row is None:
        return None
    return Subscription(
        status=row[0],
        plan=row[1],
        trial_end=row[2],
        current_period_end=row[3],
        coach_questions=row[4],
    )


def entitlement_of(user_id: UUID, now: datetime | None = None) -> Entitlement:
    """``user_id``'s entitlement right now, read from the table (never cached)."""
    return evaluate(read_subscription(user_id), now)


def is_premium(user_id: UUID, now: datetime | None = None) -> bool:
    """The gate's one question. Every enforcement point calls exactly this."""
    return entitlement_of(user_id, now).premium


__all__ = [
    "GRACE_DAYS",
    "Entitlement",
    "Subscription",
    "entitlement_of",
    "evaluate",
    "is_premium",
    "read_subscription",
    "warn_if_self_host_unlocked",
]
