"""The SUPPORT (entailment) scorer — does a cited note actually back its claim?

``docs/INTELLIGENCE.md`` section 3 says plainly that the choke point's grounding is
citation-shaped, not entailment-checked: the validator asks whether a cited id exists
and whether the sentence's hedging matches that id's grade, never whether the note's
CONTENT supports the claim. This module is the measurement that would tell us if that
gap is costing anything — an EVAL-only instrument, never imported by the product, that
runs a real NLI model over (passage, claim) pairs and reports whether the strongest
cited passage actually entails the sentence.

It does not change what ships. Nothing here gates an answer; it scores ones that
already did, the same way ``tests/grounding_eval/stats.py`` scores a ship rate.

## v2: every cited sentence, decomposed, against every non-heading passage

v1 filtered claims through ``calibration.INTERPRETIVE_RE`` — the validator's "must be
cited" rule — and fed the WHOLE sentence to the model as one hypothesis. Measured on
the baseline arm, that scored too few sentences (a 6-sentence caffeine answer with 5
citations produced exactly one claim) and its "unsupported" calls were mostly false
negatives: a compound bullet wrapping a real, well-evidenced fact in framing about the
owner ("That matters here because your…") reads as a bad entailment pair, not because
the note disagrees but because the hypothesis is three sentences doing one model's job.

v2 scores EVERY non-heading cited sentence, splits it into atomic fragments
(:mod:`tests.grounding_eval.decompose`, deterministic, no LLM), and calls a claim
supported if ANY fragment is entailed by ANY non-heading passage of ANY cited note —
reporting the max. ``INTERPRETIVE_RE`` survives only as a reported ``interpretive``
flag, a sub-split for reading the results, never the filter for which sentences get
scored.

## Why the import is lazy

``sentence_transformers`` pulls in ``torch`` — hundreds of megabytes CI must never
fetch on a plain ``uv sync --frozen``. The dependency lives in its own ``eval`` group
(``pyproject.toml``), and this module's top-level imports stay stdlib + ``numpy``
(already a default dependency) + ``healthee.*`` + ``tests.grounding_eval.*`` — the
model itself is imported only inside :func:`_load_nli_for`, on the first real call, so
the rest of this package (and every other test in the suite) can import ``support``
freely with no torch installed. Run ``uv sync --group eval`` once to add it.
"""

from __future__ import annotations

import os
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from typing import Protocol

import numpy as np
from tests.grounding_eval import decompose as decompose_mod

from healthee.insights import answer_text, calibration, manifest
from healthee.insights import passages as passages_mod

# Overridable so a different checkpoint can be A/B'd without editing code — see the
# module docstring on why the import behind it is deferred rather than done here.
_ENV_MODEL = "HEALTHEE_SUPPORT_MODEL"
DEFAULT_MODEL = "cross-encoder/nli-deberta-v3-base"
LARGE_MODEL = "cross-encoder/nli-deberta-v3-large"

# A passage this short, single-line and period-free reads as a structural LABEL, not a
# claim's evidence — see `_is_heading_only`.
_HEADING_MAX_CHARS = 60
# How many runner-up passages `_score_claim`/`rank_passages` keep, for the calibration
# sheet's "top-3 passages by entailment" — free once the predictions are in hand.
_TOP_PASSAGES = 3


class NLI(Protocol):
    """What :func:`score_answer` needs from a model: batched 3-way NLI probabilities.

    Injecting a fake satisfying this protocol is how the unit tests avoid the real
    model (and torch) entirely; the real implementation is :func:`_load_nli`'s return.
    """

    def predict(self, pairs: Sequence[tuple[str, str]]) -> Sequence[tuple[float, float, float]]:
        """``(contradiction, entailment, neutral)`` probabilities, one triple per pair."""
        ...


@dataclass(frozen=True)
class ClaimSupport:
    """One cited sentence of the answer, its atomic fragments, and its best support.

    ``best_ref``/``best_fragment``/``entailment``/``contradiction`` describe the single
    (passage, fragment) pair with the highest entailment across every fragment of this
    sentence and every non-heading passage of every note it cites — "supported by the
    strongest single piece of evidence for it", the same rule v1 documented, now applied
    per FRAGMENT rather than per whole sentence, and ``contradiction`` travels with that
    SAME winning pair rather than being maximised independently.

    ``scorable`` is ``False`` only when there was literally nothing to test the claim
    against — every cited note's passages were all heading-only, or the note carries
    zero passages at all — which is NOT the same finding as "unsupported": unsupported
    means the model saw real evidence and judged it insufficient, unscorable means the
    model was never asked. Since :mod:`decompose` now always returns at least one
    fragment (see its module docstring), the ONLY way to reach zero (premise, fragment)
    pairs is a cited note with nothing usable to premise from.
    """

    sentence: str
    cited: tuple[str, ...]
    best_ref: str | None
    entailment: float
    contradiction: float
    supported: bool
    interpretive: bool = False
    fragments: tuple[str, ...] = ()
    best_fragment: str | None = None
    scorable: bool = True


@dataclass(frozen=True)
class SupportScore:
    """The whole-answer tally :func:`score_answer` returns.

    ``unscorable`` counts claims that had zero (premise, fragment) pairs to test —
    see :attr:`ClaimSupport.scorable`. It is a SUBSET of claims not reflected in
    ``supported``'s complement being "unsupported": a caller computing a supported
    RATE should use ``cited_claims - unscorable`` as the denominator, not
    ``cited_claims``, or an unscorable claim silently reads as a failed one.
    """

    claims: int
    cited_claims: int
    supported: int
    threshold: float
    details: tuple[ClaimSupport, ...]
    unscorable: int = 0


@dataclass(frozen=True)
class _Claim:
    """Internal: one selected sentence, already decomposed, before scoring."""

    sentence: str
    cited: tuple[str, ...]
    interpretive: bool
    fragments: tuple[str, ...]


def score_answer(text: str, *, threshold: float = 0.5, nli: NLI | None = None) -> SupportScore:
    """Score every cited sentence of ``text`` against its cited notes' passages.

    A claim is any non-heading unit of :func:`answer_text.sentence_units` that cites at
    least one note id the manifest recognises — every such sentence, not only the ones
    matching :data:`calibration.INTERPRETIVE_RE` (v1's filter; kept here only as the
    reported ``interpretive`` flag, a sub-split for reading results). An uncited
    sentence, or one citing only unknown ids, makes no claim to score at all: there is
    nothing checkable about a sentence with nothing to check it against.

    Each claim is split into atomic fragments (:mod:`decompose`, deterministic, no
    LLM); a claim is supported if ANY fragment is entailed by ANY non-heading passage of
    ANY cited note, and the reported entailment/contradiction/best_ref/best_fragment
    describe that single winning (passage, fragment) pair. All (premise, fragment)
    pairs for the whole answer go to one ``nli.predict`` call, never one per claim.

    A cited note that carries zero usable (non-heading) passages leaves the claim
    ``scorable=False`` — a distinct state from ``supported=False``: unscorable means
    there was nothing to test it against, not that the model saw evidence and rejected
    it. See :class:`ClaimSupport` and :class:`SupportScore` for the distinction.
    """
    claims = [c for unit in answer_text.sentence_units(text) if (c := _claim_from_unit(unit))]
    if not claims:
        return SupportScore(claims=0, cited_claims=0, supported=0, threshold=threshold, details=())

    pairs, spans = _build_pairs(claims)
    predictions = (nli or _load_nli()).predict(pairs) if pairs else []
    details = tuple(
        _score_claim(claim, predictions[start:end], meta, threshold)
        for claim, (start, end, meta) in zip(claims, spans, strict=True)
    )
    cited_claims = sum(1 for d in details if d.cited)
    supported = sum(1 for d in details if d.supported)
    unscorable = sum(1 for d in details if not d.scorable)
    return SupportScore(
        claims=len(claims),
        cited_claims=cited_claims,
        supported=supported,
        threshold=threshold,
        details=details,
        unscorable=unscorable,
    )


def rank_passages(
    sentence: str,
    cited: Sequence[str],
    fragments: Sequence[str],
    *,
    nli: NLI | None = None,
    top_n: int = _TOP_PASSAGES,
) -> list[dict[str, str | float]]:
    """Every non-heading passage ``cited`` notes offer, ranked by its own best entailment
    across ``fragments`` — :func:`score_answer`'s pairing rule, exposed read-only so
    ``tests.grounding_eval.calibrate`` can show a human the evidence behind a claim
    without re-deriving how the winner is picked a second time. ``[]`` when there is
    nothing to rank (no cited note carries a usable passage).
    """
    claim = _Claim(sentence, tuple(cited), False, tuple(fragments) or (sentence,))
    pairs, spans = _build_pairs([claim])
    if not pairs:
        return []
    predictions = (nli or _load_nli()).predict(pairs)
    _start, _end, meta = spans[0]
    ranked = _rank_by_ref(meta, predictions)
    return [
        {"ref": ref, "text": text, "entailment": entailment}
        for ref, text, entailment, _contradiction, _fragment in ranked[:top_n]
    ]


def _claim_from_unit(unit: answer_text.Unit) -> _Claim | None:
    """A selected claim for ``unit``, or ``None`` if it makes nothing checkable."""
    if unit.heading:
        return None
    cited = _cited_known_ids(unit.text)
    if not cited:
        return None
    return _Claim(
        sentence=unit.text,
        cited=cited,
        interpretive=bool(calibration.INTERPRETIVE_RE.search(unit.text)),
        fragments=tuple(decompose_mod.decompose(unit.text)),
    )


def _cited_known_ids(sentence: str) -> tuple[str, ...]:
    """Note ids ``sentence`` cites that actually exist in the manifest, sorted."""
    ids, _personal = answer_text.extract_citations(sentence)
    known = manifest.note_ids()
    return tuple(sorted(i for i in ids if i in known))


def _is_heading_only(passage: passages_mod.Passage) -> bool:
    """True for a passage that is a structural label, never a claim's evidence.

    Two shapes: an ATX heading line the chunker kept atomic — a note's own H1 title
    routinely becomes ``note_id#p0`` this way, since ``passages._ATX_RE`` matches H1
    through H6 alike (measured: ``strength_training_mortality#p0`` is literally
    ``"# Strength training and mortality"``) — and a short, single-line, period-free
    fragment that reads as a group LABEL rather than a sentence (the corpus's other
    sub-heading spelling: a column-zero bold span with no ``###`` at all, e.g.
    ``injury_prevention``'s ``"**Training load — the primary lever**"``).

    Known false positive: a genuinely short, punctuation-free single-line passage (a
    one-cell table row, a terse directive with no full stop) would also match the
    second rule and be wrongly excluded as a premise — measured to be rare in this
    corpus's ``## The evidence`` bullets, which run well past 60 characters.
    """
    text = passage.text.strip()
    if not text:
        return True
    if text.startswith("#"):
        return True
    return "\n" not in text and len(text) <= _HEADING_MAX_CHARS and "." not in text


def _build_pairs(
    claims: Sequence[_Claim],
) -> tuple[list[tuple[str, str]], list[tuple[int, int, list[tuple[str, str, str]]]]]:
    """Every (passage_text, fragment_text) pair for every claim's cited notes' non-heading
    passages, plus each claim's ``[start, end)`` slice of ``pairs`` and, parallel to it,
    each pair's ``(ref, passage_text, fragment_text)`` — everything the scorer needs to
    name where its winner came from without a second lookup."""
    pairs: list[tuple[str, str]] = []
    spans: list[tuple[int, int, list[tuple[str, str, str]]]] = []
    for claim in claims:
        start = len(pairs)
        meta: list[tuple[str, str, str]] = []
        for note_id in claim.cited:
            for passage in passages_mod.passages(note_id):
                if _is_heading_only(passage):
                    continue
                for fragment in claim.fragments:
                    pairs.append((passage.text, fragment))
                    meta.append((passage.ref, passage.text, fragment))
        spans.append((start, len(pairs), meta))
    return pairs, spans


def _rank_by_ref(
    meta: list[tuple[str, str, str]], predictions: Sequence[tuple[float, float, float]]
) -> list[tuple[str, str, float, float, str]]:
    """``(ref, passage_text, entailment, contradiction, fragment)`` per distinct ref —
    the fragment/passage pair achieving that ref's OWN best entailment — sorted
    best-entailment-first."""
    best: dict[str, tuple[str, float, float, str]] = {}
    for (ref, text, fragment), (contradiction, entailment, _neutral) in zip(
        meta, predictions, strict=True
    ):
        current = best.get(ref)
        if current is None or entailment > current[1]:
            best[ref] = (text, entailment, contradiction, fragment)
    rows = [(ref, text, e, c, f) for ref, (text, e, c, f) in best.items()]
    return sorted(rows, key=lambda row: row[2], reverse=True)


def _score_claim(
    claim: _Claim,
    predictions: Sequence[tuple[float, float, float]],
    meta: list[tuple[str, str, str]],
    threshold: float,
) -> ClaimSupport:
    """One claim's result: the (passage, fragment) pair with the highest entailment wins,
    and its own contradiction score travels with it — never the max contradiction
    anywhere else."""
    if not predictions:
        # `decompose` always returns >= 1 fragment (see its module docstring), so the
        # only way to land here is every cited note's passages being all heading-only
        # or the note carrying none at all — nothing to entail from, which is UNSCORABLE,
        # not an "honest unsupported": the model was never asked, so it never rejected.
        return ClaimSupport(
            claim.sentence,
            claim.cited,
            None,
            0.0,
            0.0,
            False,
            interpretive=claim.interpretive,
            fragments=claim.fragments,
            scorable=False,
        )
    ranked = _rank_by_ref(meta, predictions)
    best_ref, _text, best_entailment, best_contradiction, best_fragment = ranked[0]
    return ClaimSupport(
        sentence=claim.sentence,
        cited=claim.cited,
        best_ref=best_ref,
        entailment=best_entailment,
        contradiction=best_contradiction,
        supported=best_entailment >= threshold,
        interpretive=claim.interpretive,
        fragments=claim.fragments,
        best_fragment=best_fragment,
    )


def _load_nli() -> NLI:
    """The configured checkpoint (:data:`_ENV_MODEL` or :data:`DEFAULT_MODEL`), cached."""
    return _load_nli_for(os.environ.get(_ENV_MODEL) or DEFAULT_MODEL)


@lru_cache(maxsize=4)
def _load_nli_for(model_name: str) -> NLI:
    """Load one named cross-encoder checkpoint once per process, on CUDA when present.

    Cached BY NAME (not a single slot) so ``calibrate --model ...`` can hold a second
    checkpoint in memory alongside the default one for an A/B report, without evicting
    it. Imported lazily — see the module docstring — so a missing ``eval`` group fails
    here, with a fix, rather than at import time for every caller of this package.
    """
    try:
        import torch  # type: ignore[import-not-found]
        from sentence_transformers import CrossEncoder  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError(
            "the support scorer needs the eval dependency group (sentence-transformers "
            "+ torch) — run `uv sync --group eval` from apps/server"
        ) from exc
    device = "cuda" if torch.cuda.is_available() else "cpu"
    return _CrossEncoderNLI(CrossEncoder(model_name, device=device))


class _CrossEncoderNLI:
    """Adapts a ``sentence_transformers.CrossEncoder`` NLI checkpoint to :class:`NLI`.

    ``cross-encoder/nli-deberta-v3-*`` checkpoints emit raw logits in ``(contradiction,
    entailment, neutral)`` order — the model card's own convention. ``apply_softmax=True``
    asks the library itself to turn those into the probabilities :class:`ClaimSupport`
    documents, rather than this module re-deriving softmax over an axis it would have to
    get right by inspection.
    """

    def __init__(self, model: object) -> None:
        self._model = model

    def predict(self, pairs: Sequence[tuple[str, str]]) -> Sequence[tuple[float, float, float]]:
        if not pairs:
            return []
        probs = np.asarray(
            self._model.predict(  # type: ignore[attr-defined]
                list(pairs), apply_softmax=True, convert_to_numpy=True
            )
        )
        return [(float(c), float(e), float(n)) for c, e, n in probs]
