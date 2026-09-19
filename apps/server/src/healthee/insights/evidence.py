"""The COACH's evidence block: passages, not whole notes (Step 2b).

Measured: `coach_evidence` embedded the SIX top-ranked notes WHOLE — ~41,000 tokens,
90% of every coach prompt, re-sent on every round of a 2-3 round question. Retrieval's
note RANKING is not the problem (pinned recall is 18/18, `retrieval.rank_notes` is
untouched); what of each note gets embedded is. Production RAG sends relevant
PASSAGES: hybrid retrieval, rank fusion, a cross-encoder rerank, then a small context
budget. This module is that, applied ONLY to the coach's own evidence block — the other
grounded surfaces (`grounded_ask`, the daily action, briefing, recs) keep embedding
whole notes via `retrieval.evidence_section`, unchanged, through `pipeline.evidence`.

## What is unchanged

`retrieval.rank_notes(question, metrics)[:top_n]` picks the SAME six notes as today —
this module never re-ranks. For each of those notes the block still carries the exact
header line (`## [id] (Grade) — name`) the validator's grade-calibration reads, and the
"Other citable notes" summaries-only catalogue for the remainder is byte-identical to
`evidence_section`'s.

## What changes: which TEXT of each note ships

For each top-N note: candidates are `passages.passages(note_id)` minus heading-only
labels (a bare `###` sub-heading or bold-only label line carries no claim — the same
exemption `validator._sentence_issues(heading=True)` gives a rendered heading). Every
remaining candidate is scored two ways — dense (cosine similarity against the question,
`embedding_index.EmbeddingIndex.all_passage_similarities`, one query embed for the
WHOLE question, reused across every note) and lexical (content-word overlap via
`retrieval._content_tokens`, the same stopword-filtered signal retrieval's own lexical
tie-break uses) — fused with Reciprocal Rank Fusion (k=60), then reranked by a small
cross-encoder (`fastembed.rerank.cross_encoder.TextCrossEncoder`,
`Xenova/ms-marco-MiniLM-L-6-v2`, ONNX/CPU, loaded once per process the same way
`embedding_index._FastEmbedder` loads its model — same cache dir, same degraded-mode
shape: a load failure logs once and falls back to the fused order, gated by
`Settings.evidence_rerank`). A note's `Coach Directives` passages (identified by
section — every note that carries directives spells the heading exactly that way,
verified against the corpus) are ALWAYS included regardless of score: the coach must
see its own directives.

## The budget

`Settings.evidence_token_budget` (default 8000, ~4 chars/token, approximate and
documented) is split across the top-N notes proportionally to the rank score
`retrieval.rank_notes_with_scores` computed for each — a note the explicit+lexical+
similarity signals ranked higher gets a bigger share — floored per note
(`_MIN_NOTE_SHARE`) so the weakest of the top-N still affords its header, its summary
and at least one passage. Each note's mandatory content (header, summary, directives)
is spent first; the remainder buys fused-then-reranked passages in order until the
share runs out, with a floor of one extra passage even when that runs the note over its
share — a passage that might answer the question is worth more than exact budget
adherence, and the note-level floor keeps the overrun small and bounded.

## The escape hatch: `get_knowledge` stays whole-note

`coach_tools.get_knowledge` is untouched and still returns `manifest.prompt_body` in
full. This module trims the UPFRONT context; the model can still pull a note's full
text mid-conversation when the trimmed block did not carry what it needed — the two are
complementary, not redundant: upfront cost is paid on every round whether or not the
model needed the depth, `get_knowledge` is paid only when it does.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from typing import Protocol

from healthee.core.config import get_settings
from healthee.core.logging import get_logger
from healthee.insights import embedding_index, retrieval
from healthee.insights import passages as passages_mod
from healthee.insights.embedding_index import EmbeddingIndexUnavailableError
from healthee.insights.manifest import ManifestNote
from healthee.insights.passages import Passage

log = get_logger(__name__)

_RRF_K = 60
_RERANK_MODEL = "Xenova/ms-marco-MiniLM-L-6-v2"
_RERANK_THREADS = 1
_RERANK_CANDIDATES = 10  # fused candidates handed to the cross-encoder, per note
_CHARS_PER_TOKEN = 4  # approx tokens = chars / 4, documented in the module docstring
_MIN_NOTE_SHARE = 0.08  # the floor: no top-N note's share can starve below this
_DIRECTIVES_SECTION = "Coach Directives"


def _approx_tokens(text: str) -> int:
    return max(1, len(text) // _CHARS_PER_TOKEN)


def _is_heading_only(passage: Passage) -> bool:
    """True for a passage that is nothing but a title or a sub-heading label.

    Reuses ``passages.py``'s OWN heading patterns rather than a second copy of them
    (standards §Duplication) — it keeps an ATX sub-heading or a bold-only label line
    atomic, its own passage, never merged into a neighbour's claim, precisely so it
    never fuses onto only one bullet of the group it labels. A label is not evidence,
    so it never competes for the budget here.
    """
    text = passage.text.strip()
    return bool(passages_mod._ATX_RE.match(text) or passages_mod._BOLD_LABEL_RE.match(text))


def _is_directive(passage: Passage) -> bool:
    """True for one of the note's ``## Coach Directives`` — always included, never scored."""
    return passage.section == _DIRECTIVES_SECTION


# ── Step 2b · dense + lexical, fused, reranked ───────────────────────────────

_warned_embedding_unavailable = False


def _passage_similarities(question: str) -> dict[str, float]:
    """Every corpus passage's cosine similarity to ``question`` — ``{}`` on fallback.

    One query embed, one matmul for the WHOLE question, shared across every top-N note
    by the caller — never repeated per note. Mirrors ``retrieval._note_similarities``'s
    failure policy exactly: only ``EmbeddingIndexUnavailableError`` degrades (logged
    once); anything else is a real bug and propagates.
    """
    global _warned_embedding_unavailable
    try:
        return embedding_index.index().all_passage_similarities(question)
    except EmbeddingIndexUnavailableError as exc:
        if not _warned_embedding_unavailable:
            log.warning(
                "embedding index unavailable (%s) — evidence passage selection falls "
                "back to lexical ranking only for the rest of this process",
                exc,
            )
            _warned_embedding_unavailable = True
        return {}


def _lexical_score(passage: Passage, q_content: frozenset[str]) -> int:
    return len(q_content & retrieval._content_tokens(passage.text))


def _fuse(
    candidates: Sequence[Passage], q_content: frozenset[str], passage_sims: dict[str, float]
) -> list[Passage]:
    """Reciprocal Rank Fusion (k=60) of the dense and lexical orderings."""
    dense_order = sorted(candidates, key=lambda p: -passage_sims.get(p.ref, 0.0))
    lexical_order = sorted(candidates, key=lambda p: (-_lexical_score(p, q_content), p.index))
    rrf: dict[str, float] = {}
    for order in (dense_order, lexical_order):
        for rank, p in enumerate(order):
            rrf[p.ref] = rrf.get(p.ref, 0.0) + 1.0 / (_RRF_K + rank + 1)
    return sorted(candidates, key=lambda p: (-rrf[p.ref], p.index))


class _Reranker(Protocol):
    def rerank(self, query: str, documents: Sequence[str]) -> Iterable[float]: ...


_RERANKER: _Reranker | None = None
_reranker_unavailable = False


def _get_reranker() -> _Reranker | None:
    """The process-wide cross-encoder, loaded once — ``None`` on a load failure.

    Same degraded-mode shape as ``embedding_index._FastEmbedder``: a load failure is
    logged once (naming the model) and every later call reuses that verdict rather than
    retrying a model that is not coming back this process.
    """
    global _RERANKER, _reranker_unavailable
    if _RERANKER is not None:
        return _RERANKER
    if _reranker_unavailable:
        return None
    from fastembed.rerank.cross_encoder import TextCrossEncoder

    settings = get_settings()
    try:
        _RERANKER = TextCrossEncoder(
            _RERANK_MODEL, cache_dir=settings.embedding_cache_dir, threads=_RERANK_THREADS
        )
    except Exception as exc:
        log.warning(
            "evidence reranker %s unavailable (%s) — evidence falls back to fused "
            "hybrid order for the rest of this process",
            _RERANK_MODEL,
            exc,
        )
        _reranker_unavailable = True
        return None
    return _RERANKER


def reset_reranker() -> None:
    """Test seam: clears the cached reranker singleton and its failure latch."""
    global _RERANKER, _reranker_unavailable
    _RERANKER = None
    _reranker_unavailable = False


def _rerank(question: str, fused: list[Passage]) -> list[Passage]:
    """Cross-encoder rerank of the top fused candidates; the rest keep fused order."""
    if not fused:
        return fused
    reranker = _get_reranker()
    if reranker is None:
        return fused
    head, tail = fused[:_RERANK_CANDIDATES], fused[_RERANK_CANDIDATES:]
    scores = list(reranker.rerank(question, [p.text for p in head]))
    reordered = [p for p, _s in sorted(zip(head, scores, strict=True), key=lambda pair: -pair[1])]
    return reordered + tail


# ── Per-note passage selection ───────────────────────────────────────────────


def _select_passages(
    note: ManifestNote,
    question: str,
    q_content: frozenset[str],
    passage_sims: dict[str, float],
    *,
    rerank: bool,
    budget_tokens: int,
) -> list[Passage]:
    """Directives (always) + as many fused/reranked extra passages as the budget buys.

    At least one extra passage ships whenever the note has one, even over budget — the
    floor the module docstring promises for the weakest of the top-N notes.
    """
    content = [p for p in passages_mod.passages(note.id) if not _is_heading_only(p)]
    directive_passages = [p for p in content if _is_directive(p)]
    candidates = [p for p in content if not _is_directive(p)]
    mandatory = _approx_tokens(note.name) + _approx_tokens(note.summary)
    mandatory += sum(_approx_tokens(p.text) for p in directive_passages)
    remaining = max(budget_tokens - mandatory, 0)
    if not candidates:
        return directive_passages
    fused = _fuse(candidates, q_content, passage_sims)
    ordered = _rerank(question, fused) if rerank else fused
    selected: list[Passage] = []
    spent = 0
    for p in ordered:
        cost = _approx_tokens(p.text)
        if selected and spent + cost > remaining:
            break
        selected.append(p)
        spent += cost
    return sorted({*directive_passages, *selected}, key=lambda p: p.index)


def _weights(scores: Sequence[float]) -> list[float]:
    """Budget shares per top-N note: proportional to rank score, floored.

    Every note is given ``_MIN_NOTE_SHARE`` OFF THE TOP, and only the REMAINDER
    (``1 - n * _MIN_NOTE_SHARE``) is split proportionally by score — not "floor each
    raw share, then re-normalise", which looks equivalent but is not: normalising a
    mix of one dominant raw share and several floored ones divides every floor back
    down by whatever the dominant share pushed the total above 1, silently starving
    the notes the floor exists to protect. This form's floor survives normalisation by
    construction, because the floor is never part of what gets re-scaled.

    An all-zero score set, or one where the floor is infeasible (``n`` too large for
    ``_MIN_NOTE_SHARE`` to fit every note), falls back to an EQUAL split.
    """
    n = len(scores)
    if n == 0:
        return []
    if n * _MIN_NOTE_SHARE >= 1.0:
        return [1.0 / n] * n
    total = sum(max(s, 0.0) for s in scores)
    if total <= 0:
        return [1.0 / n] * n
    extra = 1.0 - n * _MIN_NOTE_SHARE
    return [_MIN_NOTE_SHARE + extra * (max(s, 0.0) / total) for s in scores]


def _render_note(note: ManifestNote, selected: list[Passage]) -> str:
    lines = [f"\n## `[{note.id}]` ({note.grade}) — {note.name}", f"**Summary:** {note.summary}"]
    for p in selected:
        lines.append(f"\n#### {p.section or note.name}\n{p.text}")
    return "\n".join(lines)


_HEADER = (
    "# EVIDENCE NOTES\n"
    "Cite ONLY by id: `[note_id]`. Each note shows its evidence grade — match "
    "your wording to it. If no note covers a claim, write "
    "`No strong evidence in our base for this.`"
)


_CATALOGUE_HEADING = "\n## Every citable note (one-line summaries)"
_EXPANDED_HEADING = "\n## Expanded for this question (the most relevant notes, in passages)"


def build_evidence(
    question: str,
    metrics: list[str] | None = None,
    *,
    top_n: int = retrieval.DEFAULT_TOP_N,
    budget_tokens: int | None = None,
) -> tuple[str, list[str]]:
    """The coach's EVIDENCE NOTES markdown + the ids embedded — passages, not notes.

    Same contract as ``retrieval.evidence_section``: markdown, and the ids of the notes
    that were embedded (in FULL there, in SELECTED PASSAGES here). Ranking is delegated
    unchanged to ``retrieval.rank_notes_with_scores``, so the embedded ids are always
    exactly what ``rank_notes(question, metrics)[:top_n]`` would return.
    """
    scored = retrieval.rank_notes_with_scores(question, metrics)
    if not scored:
        return "", []
    settings = get_settings()
    budget = settings.evidence_token_budget if budget_tokens is None else budget_tokens
    top_scored = scored[:top_n]
    weights = _weights([s for _n, s in top_scored])
    q_content = retrieval._content_tokens(question)
    passage_sims = _passage_similarities(question)
    # The catalogue comes FIRST and lists EVERY note in id order, the expanded ones
    # included: that makes it byte-identical for every question and every owner, so it
    # joins the coach prompt as a provider-cached prefix (~6k tokens that used to change
    # with each question's top-N). What varies — the expanded notes — follows it.
    everyone = sorted((n for n, _score in scored), key=lambda n: n.id)
    parts = [_HEADER, _CATALOGUE_HEADING]
    parts.extend(f"- `[{n.id}]` ({n.grade}): {n.summary}" for n in everyone)
    parts.append(_EXPANDED_HEADING)
    embedded_ids: list[str] = []
    for (note, _score), weight in zip(top_scored, weights, strict=True):
        selected = _select_passages(
            note,
            question,
            q_content,
            passage_sims,
            rerank=settings.evidence_rerank,
            budget_tokens=int(budget * weight),
        )
        parts.append(_render_note(note, selected))
        embedded_ids.append(note.id)
    return "\n".join(parts), embedded_ids
