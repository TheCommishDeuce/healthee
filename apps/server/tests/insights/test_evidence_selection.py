"""Two properties of ``evidence._select_passages`` the main file's tests let through.

Found by the lead's mutation sweep (2026-09-19): keeping heading-only passages, and
returning the selection in score order instead of document order, both survived. Real
corpus, no model: similarities are handed in, so the selection is fully determined.
"""

from __future__ import annotations

from healthee.insights import evidence, passages, retrieval
from healthee.insights.manifest import by_id

_NOTE = "recovery_readiness"


def _select(sims: dict[str, float], budget: int) -> list[passages.Passage]:
    note = by_id(_NOTE)
    assert note is not None
    return evidence._select_passages(
        note,
        "zzqx",  # shares no content word with the corpus: the lexical arm is silent
        retrieval._content_tokens("zzqx"),
        sims,
        rerank=False,
        budget_tokens=budget,
    )


def test_a_heading_is_never_evidence_however_well_it_scores() -> None:
    """A bare heading matches a question's words better than any sentence can — that is
    what makes it dangerous — and says nothing. It must not spend the budget."""
    everything = passages.passages(_NOTE)
    headings = [p for p in everything if evidence._is_heading_only(p)]
    assert headings, "the fixture note must contain at least one heading-only passage"
    sims = {p.ref: (1.0 if p in headings else 0.1) for p in everything}
    selected = _select(sims, budget=100_000)
    assert not [p for p in selected if evidence._is_heading_only(p)]


def test_the_selection_reads_in_document_order_not_score_order() -> None:
    """Passages are chosen by relevance and SHOWN in the order the note wrote them: a
    note's argument runs top to bottom, and a caveat printed above the claim it
    qualifies reads as a different claim."""
    content = [
        p
        for p in passages.passages(_NOTE)
        if not evidence._is_heading_only(p) and not evidence._is_directive(p)
    ]
    assert len(content) >= 3
    late, early = content[-1], content[0]
    sims = {p.ref: 0.0 for p in content} | {late.ref: 0.9, early.ref: 0.8}
    selected = [p for p in _select(sims, budget=100_000) if not evidence._is_directive(p)]
    indices = [p.index for p in selected]
    assert late in selected and early in selected
    assert indices == sorted(indices)
