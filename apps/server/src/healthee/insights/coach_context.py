"""The coach's CONTEXT — history-rich, not a snapshot (WP5b / COACH_PROMPT.md).

COACH_PROMPT.md requires the coach reason over the person's *history and routines*,
not just today: a wide (≥30-day) metric window with trends + baselines, and the
recent logged-intervention history (fasting/caffeine/alcohol/meditation/workouts)
with enough depth to reveal a recurring schedule. Almost all of that already lives
in the v2-native ``build_context`` (today snapshot, trends, recent-daily pivot,
sleep sessions, the manual-entry log over the window, baselines, anomalies,
personal findings) — we reuse it wholesale (standards §Duplication) at a wider
default window and add today's recovery so "what should I do today?" respects it.

WP-C5 adds the third block: the person's challenges and their FROZEN OUTCOMES
(``challenge_context``). INTELLIGENCE §4 recorded both as "not present" while the
subsystem did not exist; the ledger half is COACH_ROADMAP C2 — measured personal
evidence, cited as ``[personal_finding:…]`` and never dressed as research. The
caveats that make it honest are structural and argued in that module.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from healthee.core.db import tenant_transaction
from healthee.core.tenancy import user_today
from healthee.insights import commitment_outcome, commitments, pipeline
from healthee.insights.challenge_context import challenge_section
from healthee.read.recovery import (
    STALE_RECOVERY_DIRECTIVE,
    recovery_freshness,
    recovery_score_payload,
)

# Default metric/history window for the coach — wide enough for trends + baselines
# and to expose a recurring intervention schedule (COACH_PROMPT.md history rule).
DEFAULT_COACH_DAYS = 30


def build_coach_context(
    question: str,
    user_id: UUID,
    tz: str,
    *,
    days: int = DEFAULT_COACH_DAYS,
) -> str:
    """The full coach context markdown: ``user_id``'s history/trends/logs + their recovery.

    The owner is REQUIRED (6.4b): it defaulted to the sentinel until the routers had a
    real authenticated user to thread down, and a default owner on a context builder is
    exactly how one tenant's data reaches another tenant's prompt.
    """
    context = pipeline.user_context(question, user_id, tz, days=days)
    with tenant_transaction(user_id) as cur:
        recovery = recovery_score_payload(cur, user_id, tz)
        challenges = challenge_section(cur, user_id)
    parts = [
        context,
        _recovery_block(recovery, tz),
        challenges,
        _commitments_block(user_id, tz),
        _kept_outcomes_block(user_id, tz),
    ]
    return "\n\n".join(p for p in parts if p)


def _commitments_block(user_id: UUID, tz: str) -> str:
    """What they told the coach they would do — the thing a cold start loses.

    Rendered into EVERY turn rather than fetched by a tool, because a coach that has
    to remember to look something up is a coach that forgets. It is a handful of
    short rows; the token cost is a rounding error against the evidence block.

    A due commitment is marked, and the marking is the whole point: the coach is
    told it is time to ask, and is told in the same breath that it does not know
    the answer. Nothing in this app observes whether somebody did a thing.
    """
    open_ones = commitments.open_commitments(user_id)
    if not open_ones:
        return ""
    today = user_today(tz)
    lines = ["# WHAT THEY COMMITTED TO", ""]
    for c in open_ones:
        due = " — **DUE: ask how it went**" if c.due(today) else ""
        metric = f" (should move `{c.metric}`)" if c.metric else ""
        lines.append(f'- `[{c.id}]` "{c.stated}"{metric}, check in {c.check_in_on}{due}')
    lines.append("")
    lines.append(
        "You do NOT know whether they did any of these — nothing here observes it. "
        "Ask, take their word, and call `resolve_commitment`. Never infer that one "
        "was kept because a number moved."
    )
    return "\n".join(lines)


def _kept_outcomes_block(user_id: UUID, tz: str) -> str:
    """What the metric did after a commitment they said they kept.

    The third source of this person's OWN evidence, beside the correlations in
    `context_sessions.findings_section` and the frozen challenge ledger in
    `challenge_context.challenge_section`. All three are cited the same way and
    carry their confidence, because a reader meeting them in one answer must not
    have to learn three vocabularies.

    ⛔ Co-occurring, never caused — and the confounds are printed rather than
    summarised, because "a challenge was also running" is the sentence that stops
    a delta being read as a result.
    """
    kept = commitments.kept_with_metric(user_id)
    if not kept:
        return ""
    lines = ["# AFTER WHAT THEY SAID THEY DID", ""]
    for c in kept:
        if c.metric is None:  # `kept_with_metric` filters these out; belt and braces
            continue
        out = commitment_outcome.outcome_for(
            user_id, tz, c.id, c.stated, c.metric, _made_on(c.created_at, tz)
        )
        if out.confidence == commitment_outcome.INSUFFICIENT:
            lines.append(
                f'- `[personal_finding:commitment]` "{c.stated}" — not enough measured '
                f"days either side to compare `{c.metric}` yet. Say that; do not reach "
                "for a number."
            )
            continue
        flags = ", ".join(f"{k}={v}" for k, v in sorted(out.confounds.items()) if v)
        caveat = f" ⚠ also in this window: {flags}." if flags else ""
        lines.append(
            f'- `[personal_finding:commitment]` "{c.stated}" — `{c.metric}` went '
            f"{out.before} → {out.after} ({out.delta:+}), {out.before_days} days before "
            f"vs {out.after_days} after.{caveat}"
        )
    lines.append("")
    lines.append(
        "Single-subject and observational: these moved WITH the change, and nothing "
        "here shows the change caused them. Say so, and name any confound above."
    )
    return "\n".join(lines)


def _made_on(value: Any, tz: str) -> date:
    """`created_at` as the day it was THEIR day, not UTC's.

    `created_at` is a `TIMESTAMPTZ`, so `.date()` on it is the UTC calendar date.
    For an owner five and a half hours ahead, a commitment made at 02:00 their time
    is the previous day in UTC — and this date anchors the before/after window, so
    the skew moves a day of the change into its own baseline. The instant is
    converted to their zone first, which is the same rule every other calendar
    boundary in this app follows.
    """
    if not isinstance(value, datetime):
        return value
    return value.astimezone(ZoneInfo(tz)).date()


def _recovery_block(recovery: dict | None, tz: str) -> str:
    """The owner's recovery so intensity advice respects it (deterministic, not LLM).

    Headed "Today's recovery" ONLY when it is today's. ``recovery_score_payload`` has
    always carried ``date``; this dropped it and asserted "today", so a stale score set
    the model's intensity ceiling as if it were current (``read/recovery.py``).
    """
    if not recovery:
        return ""
    factors = ", ".join(
        f"{name} {vals.get('sub')}" for name, vals in (recovery.get("factors") or {}).items()
    )
    stale = recovery_freshness(recovery, tz)
    return (
        _recovery_heading(recovery, stale)
        + f"- Factor sub-scores: {factors}.\n"
        + f"- Built-in guidance: {recovery.get('guidance', '')}\n"
        + "- Rule of thumb: low recovery ⇒ advise rest/easy and protect sleep; moderate ⇒ "
        "Zone 2 only; high ⇒ pushing is fine."
    )


def _recovery_heading(recovery: dict, stale: dict | None) -> str:
    """The heading + score line — the two lines that made the "today" claim.

    Live readiness is dropped when the score is stale, not just relabelled: the intraday
    decay only applies on the score's OWN day (``read/recovery._live_readiness`` returns
    the morning value unchanged otherwise), so quoting "live readiness" for an older day
    would name a number that has not decayed against anything.
    """
    if stale is None:
        return (
            "## Today's recovery [recovery_readiness] — let it set intensity advice\n"
            f"- Recovery {recovery['recovery']}/100, live readiness {recovery['readiness']} "
            f"({recovery['band']}).\n"
        )
    return (
        f"## Most recent recovery — from {stale['last_as_of_date']}, "
        f"{stale['age_days']} day(s) ago [recovery_readiness]\n"
        f"- Recovery {recovery['recovery']}/100 ({recovery['band']}) AS OF "
        f"{stale['last_as_of_date']}. {STALE_RECOVERY_DIRECTIVE}\n"
    )


def coach_evidence(question: str) -> str:
    """Top-ranked evidence notes for the current question — the COACH's evidence stage.

    Through ``pipeline.coach_evidence`` rather than ``insights.evidence.build_evidence``
    directly, so "the coach embeds passages, not whole notes" is a fact a seam enforces
    rather than a comment — same discipline ``pipeline.evidence`` gives every other
    surface's call to ``retrieval.evidence_section``. Ranking is unchanged: both seams
    pick the same top-N notes (``insights/evidence.py``'s module docstring).
    """
    evidence_md, _ids = pipeline.coach_evidence(question)
    return evidence_md
