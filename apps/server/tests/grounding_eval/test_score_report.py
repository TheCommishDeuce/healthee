"""The report/stats lines a scored arm unlocks — split out of ``test_score.py`` to stay
under the 400-line file gate. No network, no database: everything here is arithmetic
over hand-built records.
"""

from __future__ import annotations

from tests.grounding_eval import questions as qs
from tests.grounding_eval import report, stats
from tests.grounding_eval.records import FALLBACK, GROUNDED, EvalRun, RunRecord


def _rec(qid: str, *, outcome: str = GROUNDED, answer: str = "") -> RunRecord:
    return RunRecord(
        question_id=qid,
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=outcome,
        success=(outcome == GROUNDED),
        answer=answer,
    )


def _arm(records: list[RunRecord], label: str = "arm") -> EvalRun:
    return EvalRun(
        label=label,
        commit="abc1234",
        question_set="fp",
        repeats=1,
        started_at="2026-01-01T00:00:00+00:00",
        records=records,
    )


def _scored_rec(
    qid: str, *, cited: int, supported: int, claims: int = 3, unscorable: int = 0
) -> RunRecord:
    return RunRecord(
        question_id=qid,
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=GROUNDED,
        success=True,
        answer="text",
        support_claims=claims,
        support_cited=cited,
        support_supported=supported,
        support_threshold=0.5,
        support_unscorable=unscorable,
    )


def test_an_unscored_arms_summary_has_no_support_lines() -> None:
    arm = _arm([_rec("a", answer="text")])
    assert "SUPPORT" not in report.summary(arm)


def test_a_scored_arms_summary_shows_the_rate_with_n_and_interval() -> None:
    arm = _arm([_scored_rec("a", cited=2, supported=1), _scored_rec("b", cited=2, supported=2)])
    out = report.summary(arm)
    assert "CITATION SUPPORT" in out
    assert "3/4" in out  # 1 + 2 supported over 2 + 2 cited claims
    assert "95% CI" in out


def test_comparison_prints_the_paired_support_delta() -> None:
    before = _arm([_scored_rec("a", cited=2, supported=1)], label="before")
    after = _arm([_scored_rec("a", cited=2, supported=2)], label="after")
    out = report.comparison(before, after)
    assert "supported-citation fraction" in out


def test_latency_lines_appear_per_surface() -> None:
    coach = RunRecord(
        question_id="a",
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=GROUNDED,
        success=True,
        latency_ms=1000,
    )
    grounded = RunRecord(
        question_id="b",
        kind="surface",
        surface="grounded",
        repeat=0,
        outcome=GROUNDED,
        success=True,
        latency_ms=2000,
    )
    out = report.summary(_arm([coach, grounded]))
    assert "coach" in out and "grounded" in out
    assert "p95" in out


def test_support_records_only_counts_grounded_and_scored() -> None:
    """Both halves of the filter are load-bearing, so both are given a row that would
    slip through if the OTHER half were dropped: ``d`` is scored (``support_threshold >
    0``) but not grounded — a hand-edited or corrupted arm's shape, and exactly what the
    function's docstring promises to exclude.
    """
    non_grounded_but_scored = RunRecord(
        question_id="d",
        kind=qs.KNOWLEDGE,
        surface="coach",
        repeat=0,
        outcome=FALLBACK,
        success=False,
        answer="the honest fallback sentence",
        support_claims=3,
        support_cited=2,
        support_supported=1,
        support_threshold=0.5,
    )
    rows = [
        _scored_rec("a", cited=2, supported=1),
        _rec("b", outcome=FALLBACK),  # never scored — threshold stays 0.0
        _rec("c", answer="text"),  # grounded but never run through `score`
        non_grounded_but_scored,
    ]
    assert stats.support_records(rows) == [rows[0]]


def test_supported_citation_rate_excludes_unscorable_claims_from_the_denominator() -> None:
    """4 cited, 2 supported, 1 unscorable -> denominator is 4 - 1 = 3, not 4. Counting
    the unscorable claim in the denominator would read "we never asked" as a failure."""
    rows = [_scored_rec("a", cited=4, claims=4, supported=2, unscorable=1)]
    rate = stats.supported_citation_rate(rows)
    assert (rate.successes, rate.n) == (2, 3)


def test_summary_prints_the_unscorable_warning_only_when_present() -> None:
    with_gap = report.summary(
        _arm([_scored_rec("a", cited=4, claims=4, supported=2, unscorable=1)])
    )
    assert "1 cited claim(s) UNSCORABLE" in with_gap

    without_gap = report.summary(
        _arm([_scored_rec("b", cited=4, claims=4, supported=2, unscorable=0)])
    )
    assert "UNSCORABLE" not in without_gap
