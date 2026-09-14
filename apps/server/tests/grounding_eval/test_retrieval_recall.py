"""Retrieval recall@6 — a free, deterministic proxy for "did the eval embed the right
notes", measurable without spending money on a model or reaching a database.

``recall_at_k`` (``recall.py``) calls ``rank_notes`` directly, which is a pure function
over the question text and the corpus manifest — no LLM, no DB, no network. This file
pins today's measured numbers as a ratchet: a future change (to retrieval, or to the
knowledge corpus it ranks) that LOSES a pinned hit fails loudly here, for nothing, before
anyone pays for a paid eval arm to notice the same thing.

Measured 2026-09-14 at commit 314d28a: recall@6 = 18/18 = 1.000 (100%) over the 18
answer-expecting questions that carry an ``expects_any_of`` pin (``o_stock``,
``o_protein``, ``i_month_compare`` and ``i_one_change`` are deliberate non-expectations,
not misses; safety and ``surface`` questions carry none — see ``test_harness.py``).

## A discrepancy, reported rather than forced

The task that produced this file was briefed against an EARLIER measurement in which
five questions (``i_drinks_recovery``, ``i_tired``, ``i_walking_worth``,
``i_train_or_rest``, ``d_sleep_hours``) missed — retrieval handed them notes about
critical speed, napping and biological age instead of the recovery/alcohol/steps notes
that should have grounded them, and they were meant to be pinned as misses for a future
retrieval change to fix. While this file was being written, a concurrent, uncommitted
edit to ``packages/knowledge/**`` (alias additions ONLY — ``git diff --stat
packages/knowledge`` shows notes/manifest touched, ``src/healthee/insights/retrieval.py``
untouched by anyone) gave ``alcohol_sleep``, ``steps_mortality``, ``mvpa_minutes_mortality``,
``recovery_readiness``, ``sleep_need_debt`` and ``sleep_and_recovery`` new plain-language
aliases — "drinks", "walk"/"walking", "wiped out", "push hard"/"take it easy", "hours of
sleep" — that now match all five questions directly. Re-measured just before this file
was finalized: all five are HITS. Per instruction, that is not forced back into a false
"still misses" assertion; ``test_the_briefs_named_miss_targets_already_hit_on_todays_corpus``
below is the report, checked rather than left as a comment nobody re-verifies.
"""

from __future__ import annotations

from tests.grounding_eval import questions as qs
from tests.grounding_eval.question_types import EvalQuestion
from tests.grounding_eval.recall import recall_at_k

from healthee.insights.retrieval import DEFAULT_TOP_N, rank_notes

# The exact set of question ids that hit @ DEFAULT_TOP_N, measured today (see module
# docstring). A future run producing a DIFFERENT set — losing a hit OR gaining a new one
# — means retrieval (or the corpus it ranks) moved, and this pin must move with it
# DELIBERATELY: update this frozenset, re-measure, and say why in the commit.
_PINNED_HITS: frozenset[str] = frozenset(
    {
        "k_alcohol",
        "k_caffeine",
        "k_vo2max",
        "d_rhr",
        "d_sleep_hours",
        "d_steps",
        "c_sleep_focus",
        "c_train_today",
        "i_train_or_rest",
        "i_tired",
        "i_nap",
        "i_hrv_worried",
        "i_good_sleep",
        "i_drinks_recovery",
        "i_walking_worth",
        "i_pulse_healthy",
        "i_short_night",
        "i_sleep_tonight_plain",
    }
)

# The five questions the brief measured as misses against an earlier corpus state — see
# the module docstring's discrepancy note. Kept as their own constant so the report test
# names exactly what it is reporting on, independent of the ratchet above.
_BRIEFS_NAMED_MISS_TARGETS: frozenset[str] = frozenset(
    {"i_drinks_recovery", "i_tired", "i_walking_worth", "i_train_or_rest", "d_sleep_hours"}
)


def _print_recall_table(questions: tuple[EvalQuestion, ...]) -> None:
    """Question, hit/miss, and the top-k ids — printed so a failure is diagnosable
    without re-running anything by hand."""
    for question in questions:
        if not question.expects_any_of:
            continue
        top_ids = [note.id for note in rank_notes(question.text, question.metrics)[:DEFAULT_TOP_N]]
        hit = bool(set(top_ids) & set(question.expects_any_of))
        mark = "HIT " if hit else "MISS"
        print(f"{mark}  {question.id:22s} expects={question.expects_any_of} top={top_ids}")


def test_recall_matches_the_pinned_baseline() -> None:
    """The regression gate: today's per-question hit set, exactly.

    Both directions are asserted by comparing the sets outright — losing a hit AND
    gaining an unpinned one both fail, so a lucky improvement is caught and named
    (update ``_PINNED_HITS`` deliberately) exactly like a regression is.
    """
    rate, hits = recall_at_k(qs.QUESTIONS, DEFAULT_TOP_N)
    hit_ids = frozenset(qid for qid, hit in hits.items() if hit)
    print(f"recall@{DEFAULT_TOP_N} = {rate:.3f} ({len(hit_ids)}/{len(hits)})")
    if hit_ids != _PINNED_HITS:
        _print_recall_table(qs.QUESTIONS)
    assert hit_ids == _PINNED_HITS, (
        f"retrieval recall moved — lost {_PINNED_HITS - hit_ids}, "
        f"gained {hit_ids - _PINNED_HITS}; update _PINNED_HITS deliberately if intended"
    )


def test_the_briefs_named_miss_targets_already_hit_on_todays_corpus() -> None:
    """DISCREPANCY REPORT — see the module docstring's full explanation.

    These five were meant to be pinned as misses for a future retrieval.py change to
    turn into hits. A concurrent, alias-only edit to packages/knowledge already did that
    before retrieval.py was touched. Reported here as a checked fact rather than forced
    into a false "still misses" assertion.
    """
    named = tuple(q for q in qs.QUESTIONS if q.id in _BRIEFS_NAMED_MISS_TARGETS)
    assert {q.id for q in named} == _BRIEFS_NAMED_MISS_TARGETS
    _, hits = recall_at_k(named, DEFAULT_TOP_N)
    assert set(hits) == _BRIEFS_NAMED_MISS_TARGETS
    assert all(hits.values()), hits


def test_recall_at_k_ignores_questions_with_no_expectation() -> None:
    """``o_stock``/``o_protein``/``i_month_compare``/``i_one_change`` opt out of scoring
    entirely — they must not silently count as either a hit or a miss."""
    unscored = [q for q in qs.QUESTIONS if not q.expects_any_of]
    assert unscored  # the opt-outs still exist in the set
    rate, hits = recall_at_k(unscored, DEFAULT_TOP_N)
    assert hits == {}
    assert rate == 0.0


def test_recall_at_k_returns_zero_rather_than_dividing_by_zero() -> None:
    """No pinned question in the slice must report an honest 0.0, never a crash."""
    only_safety = tuple(q for q in qs.QUESTIONS if q.kind == qs.SAFETY)
    rate, hits = recall_at_k(only_safety, DEFAULT_TOP_N)
    assert (rate, hits) == (0.0, {})
