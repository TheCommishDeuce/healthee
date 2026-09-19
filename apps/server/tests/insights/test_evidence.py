"""``insights/evidence.py`` — the coach's passage-level evidence block (Step 2b).

Every test here is network-free: the dense (embedding) signal is stubbed to ``{}``
(degrading to lexical-only, same fallback ``retrieval.py`` ships) unless a test
explicitly wants to exercise it, and the cross-encoder reranker is stubbed to ``None``
(fused order) unless a test explicitly injects a fake one. Fusion/rerank/budget unit
tests construct their own small, fully-controlled ``Passage``/``ManifestNote`` fakes
rather than leaning on real corpus wording — real corpus tests (the contract tests, the
budget sweep, the eval-question check) are grouped separately below. The real reranker
model is exercised only in the opt-in smoke test at the bottom, gated on
``HEALTHEE_EMBED_MODEL_TESTS=1`` — the same flag ``test_embedding_index.py`` uses.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Sequence

import pytest
from tests.grounding_eval import questions as qs

from healthee.insights import evidence, retrieval
from healthee.insights.manifest import ManifestNote, by_id
from healthee.insights.passages import Passage

# Captured at IMPORT time, before the autouse fixture below ever patches the module
# attribute of the same name — the one test that means to exercise the REAL loader
# (the degrade-on-failure test) calls this instead of ``evidence._get_reranker``.
_REAL_GET_RERANKER = evidence._get_reranker


@pytest.fixture(autouse=True)
def _no_real_models(monkeypatch: pytest.MonkeyPatch) -> None:
    """Default stubs: no embedding index, no reranker — pure lexical + fused order."""
    monkeypatch.setattr(retrieval.embedding_index, "note_scores", lambda _q: {})
    retrieval.reset_embedding_warning()
    monkeypatch.setattr(evidence, "_passage_similarities", lambda _q: {})
    monkeypatch.setattr(evidence, "_get_reranker", lambda: None)
    evidence.reset_reranker()


def _note(**overrides: object) -> ManifestNote:
    defaults: dict[str, object] = {
        "id": "test_note",
        "name": "Test Note",
        "grade": "Established",
        "summary": "A short summary of the test note.",
        "path": "",
        "category": "x",
    }
    defaults.update(overrides)
    return ManifestNote(**defaults)  # type: ignore[arg-type]


def _passage(note_id: str, index: int, section: str, text: str) -> Passage:
    return Passage(note_id=note_id, index=index, section=section, text=text)


# ── contract: same six notes, header + summary always present ───────────────


def test_the_embedded_notes_match_rank_notes_top_n() -> None:
    question = "how does alcohol before bed affect sleep?"
    _md, embedded_ids = evidence.build_evidence(question)
    expected = [n.id for n in retrieval.rank_notes(question)[: retrieval.DEFAULT_TOP_N]]
    assert embedded_ids == expected


def test_every_embedded_note_carries_its_header_and_summary() -> None:
    question = "what does vo2max mean for my health?"
    md, embedded_ids = evidence.build_evidence(question)
    for note_id in embedded_ids:
        note = by_id(note_id)
        assert note is not None
        assert f"## `[{note_id}]` ({note.grade}) — {note.name}" in md
        assert f"**Summary:** {note.summary}" in md


def _prefix(md: str) -> str:
    """Everything before the per-question part: the header and the full catalogue."""
    return md.split(evidence._EXPANDED_HEADING)[0]


def test_the_catalogue_is_a_byte_identical_prefix_for_every_question() -> None:
    """The point of putting it first: a provider's prompt cache matches a byte-identical
    PREFIX, so the catalogue must not depend on the question, its metrics, or top_n."""
    a, _ = evidence.build_evidence("how has my sleep been lately?")
    b, _ = evidence.build_evidence("should I train hard today?", ["hrv_sleep_avg"], top_n=3)
    assert _prefix(a) == _prefix(b)
    assert evidence._CATALOGUE_HEADING in _prefix(a)


def test_the_catalogue_lists_every_note_once_in_id_order_expanded_ones_included() -> None:
    md, embedded = evidence.build_evidence("what does vo2max mean for my health?")
    lines = [ln for ln in _prefix(md).splitlines() if ln.startswith("- `[")]
    ids = [ln.split("`[")[1].split("]`")[0] for ln in lines]
    assert ids == sorted(n.id for n in retrieval.all_notes())
    assert set(embedded) <= set(ids)


def test_the_expanded_notes_follow_the_catalogue() -> None:
    md, embedded = evidence.build_evidence("what does vo2max mean for my health?")
    after = md.split(evidence._EXPANDED_HEADING)[1]
    for note_id in embedded:
        assert f"## `[{note_id}]`" in after
        assert f"## `[{note_id}]`" not in _prefix(md)


def test_an_empty_corpus_question_still_returns_the_empty_contract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(retrieval, "all_notes", lambda: ())
    md, ids = evidence.build_evidence("anything")
    assert (md, ids) == ("", [])


def test_a_passage_that_answers_outranks_one_that_does_not(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """End-to-end, under a budget too tight for all of a note's passages: the ANSWERING
    one survives selection and the one the question doesn't touch does not.

    Checked by presence, not by position in the rendered text: ``_select_passages``
    always renders whatever it selected back in DOCUMENT order (so prose reads in the
    order the note wrote it), so a generous budget selects both passages and puts the
    filler one first regardless of relevance — the observable effect of ranking is
    which passages survive a tight budget, not where a selected one lands on the page.
    A third, equally-irrelevant filler passage is included for the same reason the
    fusion tests above use three: RRF over exactly two candidates that each win one
    arm outright ties EXACTLY, by construction — see those tests' docstrings.
    """
    a = _passage("napping", 0, "Body", "An unrelated filler passage, long enough to count.")
    b = _passage("napping", 1, "Body", "This passage directly answers the napping sleep debt.")
    c = _passage("napping", 2, "Body", "A second unrelated filler passage, long enough too.")
    monkeypatch.setattr(evidence.passages_mod, "passages", lambda _nid: (a, b, c))
    monkeypatch.setattr(
        evidence, "_passage_similarities", lambda _q: {a.ref: 0.0, b.ref: 0.9, c.ref: 0.0}
    )
    question = "napping and sleep debt — please answer directly"
    md, embedded_ids = evidence.build_evidence(question, top_n=1, budget_tokens=5)
    assert embedded_ids == ["napping"]
    assert b.text in md
    assert a.text not in md
    assert c.text not in md


# ── directives: always present, regardless of score or budget ───────────────


def test_directives_are_always_included_regardless_of_score_or_budget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Mutation target: dropping directives from ``_select_passages`` fails this test."""
    note = _note()
    directive = _passage(note.id, 0, "Coach Directives", "1. A safety-critical instruction.")
    candidate = _passage(note.id, 1, "Body", "An ordinary claim with real content in it.")
    monkeypatch.setattr(evidence.passages_mod, "passages", lambda _nid: (directive, candidate))
    for budget in (0, 100_000):
        selected = evidence._select_passages(
            note, "irrelevant", frozenset(), {}, rerank=False, budget_tokens=budget
        )
        assert directive in selected, budget


# ── budget: respected, and floored so the weakest top-N note still gets a passage ──


def test_a_bigger_budget_yields_more_selected_passages(monkeypatch: pytest.MonkeyPatch) -> None:
    """Mutation target: an ignored ``budget_tokens`` makes small == large."""
    note = _note()
    directive = _passage(note.id, 0, "Coach Directives", "1. Directive text.")
    candidates = [
        _passage(note.id, i, "Body", f"Candidate passage {i} with real content in it, plenty.")
        for i in range(1, 6)
    ]
    monkeypatch.setattr(evidence.passages_mod, "passages", lambda _nid: (directive, *candidates))
    small = evidence._select_passages(note, "q", frozenset(), {}, rerank=False, budget_tokens=1)
    large = evidence._select_passages(
        note, "q", frozenset(), {}, rerank=False, budget_tokens=100_000
    )
    assert len(large) > len(small)
    assert sum(len(p.text) for p in large) > sum(len(p.text) for p in small)


def test_the_sixth_notes_floor_still_buys_a_passage() -> None:
    """``_weights`` floors every top-N note's share (``_MIN_NOTE_SHARE``)."""
    weights = evidence._weights([100.0, 1.0, 1.0, 1.0, 1.0, 0.0])
    assert len(weights) == 6
    assert all(w >= evidence._MIN_NOTE_SHARE - 1e-9 for w in weights)
    assert pytest.approx(sum(weights)) == 1.0


def test_weights_split_evenly_when_nothing_scored() -> None:
    """The all-zero fallback (retrieval's own alphabet tie-break) — no ZeroDivisionError."""
    assert evidence._weights([0.0, 0.0, 0.0]) == [pytest.approx(1 / 3)] * 3


def test_the_real_corpus_stays_under_budget_for_every_eval_question() -> None:
    """No network needed: dense is stubbed to ``{}``, so this is the lexical+fused path
    over the REAL corpus — the per-note floor's bounded overrun is the only slack.

    Measured against the EXPANDED portion only: the catalogue ahead of it is a fixed,
    one-line-per-note list that is identical for every question (and provider-cached),
    so it was never inside what ``evidence_token_budget`` bounds.
    """
    tolerance = 1.2  # measured worst case across the eval set is ~1.15x
    budget = evidence.get_settings().evidence_token_budget
    for question in qs.QUESTIONS:
        md, _ids = evidence.build_evidence(question.text, question.metrics)
        expanded = md.split(evidence._EXPANDED_HEADING)[1]
        assert evidence._approx_tokens(expanded) <= budget * tolerance, question.id


def test_every_eval_question_with_an_expected_note_embeds_it() -> None:
    """The block-level restatement of ``recall.py``'s guarantee (INTELLIGENCE §3)."""
    for question in qs.QUESTIONS:
        if not question.expects_any_of:
            continue
        _md, embedded_ids = evidence.build_evidence(question.text, question.metrics)
        assert set(embedded_ids) & set(question.expects_any_of), question.id


# ── hybrid fusion: dense arm, lexical arm, RRF k ─────────────────────────────


def test_rrf_k_is_pinned_at_60() -> None:
    """Mutation target: a changed ``_RRF_K`` moves every fused score silently."""
    assert evidence._RRF_K == 60


def test_the_dense_signal_can_decide_the_fused_order() -> None:
    """Three candidates, zero lexical signal: only DENSE similarity can pick a winner.

    Two candidates would not do here — with exactly two, whichever wins the dense arm
    always loses the lexical arm's index tie-break by exactly the same margin, so their
    RRF totals are mathematically IDENTICAL regardless of how strong the dense edge is,
    and the final tie-break (index) would pick the same winner whether or not dense ran
    at all. A third candidate breaks that symmetry.
    """
    a, b, c = (
        _passage("n", 0, "Body", "alpha"),
        _passage("n", 1, "Body", "beta"),
        _passage("n", 2, "Body", "gamma"),
    )
    sims = {a.ref: 0.1, b.ref: 0.9, c.ref: 0.5}
    fused = evidence._fuse([a, b, c], frozenset(), sims)
    assert fused[0] is b, "the passage with the highest DENSE similarity must rank first"


def test_the_lexical_signal_can_decide_the_fused_order() -> None:
    """Three candidates, no dense scores at all: only LEXICAL overlap can pick a winner
    (see the dense test above for why two candidates cannot isolate one arm)."""
    a = _passage("n", 0, "Body", "unrelated words about nothing in particular")
    b = _passage("n", 1, "Body", "espresso caffeine afternoon disrupts sleep onset badly")
    c = _passage("n", 2, "Body", "caffeine afternoon mention only")
    q_content = retrieval._content_tokens("does an afternoon espresso disrupt sleep")
    scores = [evidence._lexical_score(p, q_content) for p in (a, b, c)]
    assert scores[1] > scores[2] > scores[0]  # the premise: b > c > a on lexical overlap
    fused = evidence._fuse([a, b, c], q_content, {})
    assert fused[0] is b, "the passage with the highest LEXICAL overlap must rank first"


# ── rerank: applied when enabled, skipped when disabled, degrades on load failure ──


class _ReverseReranker:
    """A fake cross-encoder that scores strictly by position — last document wins."""

    def rerank(self, query: str, documents: Sequence[str]) -> list[float]:  # noqa: ARG002
        return list(range(len(documents)))


def test_rerank_with_no_reranker_available_returns_the_fused_order_unchanged() -> None:
    """The default fixture's ``_get_reranker`` returns ``None`` — the degraded path."""
    a, b = _passage("n", 0, "Body", "alpha"), _passage("n", 1, "Body", "beta")
    assert evidence._rerank("question", [a, b]) == [a, b]


def test_rerank_applies_the_rerankers_own_order(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(evidence, "_get_reranker", lambda: _ReverseReranker())
    a, b = _passage("n", 0, "Body", "alpha"), _passage("n", 1, "Body", "beta")
    reranked = evidence._rerank("question", [a, b])
    assert reranked[0] is b, "the reranker's own order must win when rerank is applied"


def _rig_two_candidates(monkeypatch: pytest.MonkeyPatch) -> tuple[ManifestNote, Passage, Passage]:
    """A note with one directive + two candidates, and a reranker that reverses them.

    ``_select_passages`` sorts its RETURN by document index (so the render stays in
    reading order), which means a generous budget hides whether rerank ran at all — both
    candidates survive either way, in the same order. A budget that can only afford ONE
    extra passage is what makes the reranker's choice observable: fused order picks the
    first-indexed candidate, reranked order picks whichever the reranker preferred.
    """
    note = _note()
    directive = _passage(note.id, 0, "Coach Directives", "1. Directive text.")
    a = _passage(note.id, 1, "Body", "alpha candidate passage with real content here.")
    b = _passage(note.id, 2, "Body", "beta candidate passage with real content here too.")
    monkeypatch.setattr(evidence.passages_mod, "passages", lambda _nid: (directive, a, b))
    monkeypatch.setattr(evidence, "_get_reranker", lambda: _ReverseReranker())
    return note, a, b


def test_rerank_disabled_by_setting_leaves_the_fused_order_alone(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Mutation target: a rerank stage that runs even when ``rerank=False``."""
    note, a, _b = _rig_two_candidates(monkeypatch)
    selected = evidence._select_passages(note, "q", frozenset(), {}, rerank=False, budget_tokens=1)
    extra = [p for p in selected if p.section != "Coach Directives"]
    assert extra == [a], "disabled rerank must keep the fused (document) order"


def test_rerank_enabled_lets_the_reranker_decide_the_tight_budgets_one_pick(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Mutation target: rerank enabled but silently not applied."""
    note, _a, b = _rig_two_candidates(monkeypatch)
    selected = evidence._select_passages(note, "q", frozenset(), {}, rerank=True, budget_tokens=1)
    extra = [p for p in selected if p.section != "Coach Directives"]
    assert extra == [b], "rerank=True must let the reranker's own order decide the floor pick"


def test_a_reranker_that_fails_to_load_degrades_to_fused_order_with_one_warning(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    class _BoomCrossEncoder:
        def __init__(self, *_a: object, **_k: object) -> None:
            raise RuntimeError("simulated: no cached file, no network")

    monkeypatch.setattr("fastembed.rerank.cross_encoder.TextCrossEncoder", _BoomCrossEncoder)
    evidence.reset_reranker()
    # The REAL loader, not the autouse fixture's stub of the same name — this test
    # exists to prove what that stub otherwise hides.
    with caplog.at_level(logging.WARNING, logger="healthee.insights.evidence"):
        assert _REAL_GET_RERANKER() is None
        assert _REAL_GET_RERANKER() is None  # cached failure — not retried
    warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert len(warnings) == 1
    assert "reranker" in warnings[0].message


# ── opt-in: the real reranker model (never runs in CI) ────────────────────


@pytest.mark.skipif(
    os.environ.get("HEALTHEE_EMBED_MODEL_TESTS") != "1",
    reason="downloads/loads the real ONNX reranker — opt in with HEALTHEE_EMBED_MODEL_TESTS=1",
)
def test_real_reranker_scores_a_relevant_passage_higher() -> None:
    evidence.reset_reranker()
    reranker = evidence._get_reranker()
    assert reranker is not None
    scores = list(
        reranker.rerank(
            "does alcohol affect my sleep",
            ["alcohol reduces REM sleep at night", "the weather today is sunny"],
        )
    )
    assert scores[0] > scores[1]
