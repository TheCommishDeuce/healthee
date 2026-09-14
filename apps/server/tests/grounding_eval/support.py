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

## Why the import is lazy

``sentence_transformers`` pulls in ``torch`` — hundreds of megabytes CI must never
fetch on a plain ``uv sync --frozen``. The dependency lives in its own ``eval`` group
(``pyproject.toml``), and this module's top-level imports stay stdlib + ``numpy``
(already a default dependency) + ``healthee.*`` + ``tests.grounding_eval.*`` — the
model itself is imported only inside :func:`_load_nli`, on the first real call, so the
rest of this package (and every other test in the suite) can import ``support`` freely
with no torch installed. Run ``uv sync --group eval`` once to add it.
"""

from __future__ import annotations

import os
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from typing import Protocol

import numpy as np

from healthee.insights import answer_text, calibration, manifest
from healthee.insights import passages as passages_mod

# Overridable so a different checkpoint can be A/B'd without editing code — see the
# module docstring on why the import behind it is deferred rather than done here.
_ENV_MODEL = "HEALTHEE_SUPPORT_MODEL"
DEFAULT_MODEL = "cross-encoder/nli-deberta-v3-base"


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
    """One interpretive sentence of the answer, and whether its citation backs it up."""

    sentence: str
    cited: tuple[str, ...]
    best_ref: str | None
    entailment: float
    contradiction: float
    supported: bool


@dataclass(frozen=True)
class SupportScore:
    """The whole-answer tally :func:`score_answer` returns."""

    claims: int
    cited_claims: int
    supported: int
    threshold: float
    details: tuple[ClaimSupport, ...]


def score_answer(text: str, *, threshold: float = 0.5, nli: NLI | None = None) -> SupportScore:
    """Score every interpretive, cited claim in ``text`` against its cited notes' passages.

    A claim is a non-heading unit of :func:`answer_text.sentence_units` matching
    :data:`calibration.INTERPRETIVE_RE` — the same "is this a claim, not a report"
    test the validator already applies. An uncited claim (or one citing only ids the
    manifest doesn't recognise) counts in ``claims`` but not ``cited_claims``: it is
    already an issue the validator would have caught, and entailment has nothing to
    check.

    Every passage of every cited note is a candidate premise; the reported entailment
    is the MAX over all of them (:func:`healthee.insights.passages.passages`), and
    ``contradiction`` is read off that SAME best-entailment passage, not maximised
    independently — a claim is "supported" by the strongest single piece of evidence
    for it, and its contradiction score describes that evidence, not some other
    passage entirely. All (premise, claim) pairs for the whole answer go to one
    ``nli.predict`` call, never one call per claim or per passage.

    A cited note that exists in the manifest but carries zero passages (a body the
    chunker couldn't split, or an empty one) cannot support anything: that claim
    scores ``supported=False`` with ``best_ref=None`` rather than being silently
    skipped or, worse, marked supported by omission.
    """
    claims = [
        (unit.text, _cited_known_ids(unit.text))
        for unit in answer_text.sentence_units(text)
        if not unit.heading and calibration.INTERPRETIVE_RE.search(unit.text)
    ]
    if not claims:
        return SupportScore(claims=0, cited_claims=0, supported=0, threshold=threshold, details=())

    pairs, spans = _build_pairs(claims)
    predictions = (nli or _load_nli()).predict(pairs) if pairs else []
    details = tuple(
        _score_claim(sentence, cited, refs, predictions[start:end], threshold)
        for (sentence, cited), (start, end, refs) in zip(claims, spans, strict=True)
    )
    cited_claims = sum(1 for d in details if d.cited)
    supported = sum(1 for d in details if d.supported)
    return SupportScore(
        claims=len(claims),
        cited_claims=cited_claims,
        supported=supported,
        threshold=threshold,
        details=details,
    )


def _cited_known_ids(sentence: str) -> tuple[str, ...]:
    """Note ids ``sentence`` cites that actually exist in the manifest, sorted."""
    ids, _personal = answer_text.extract_citations(sentence)
    known = manifest.note_ids()
    return tuple(sorted(i for i in ids if i in known))


def _build_pairs(
    claims: list[tuple[str, tuple[str, ...]]],
) -> tuple[list[tuple[str, str]], list[tuple[int, int, list[str]]]]:
    """Every (passage_text, claim_sentence) pair for every cited claim, plus, per
    claim, the ``[start, end)`` slice of ``pairs`` it owns and the passage refs at
    those positions (parallel to the slice, so results can be read back per-claim
    after one batched ``predict`` call)."""
    pairs: list[tuple[str, str]] = []
    spans: list[tuple[int, int, list[str]]] = []
    for sentence, cited in claims:
        start = len(pairs)
        refs: list[str] = []
        for note_id in cited:
            for passage in passages_mod.passages(note_id):
                pairs.append((passage.text, sentence))
                refs.append(passage.ref)
        spans.append((start, len(pairs), refs))
    return pairs, spans


def _score_claim(
    sentence: str,
    cited: tuple[str, ...],
    refs: list[str],
    predictions: Sequence[tuple[float, float, float]],
    threshold: float,
) -> ClaimSupport:
    """One claim's result: the passage with the highest entailment wins, and its own
    contradiction score travels with it — never the max contradiction anywhere else."""
    if not predictions:
        # Either uncited, or every cited id exists but carries zero passages: neither
        # case has anything to entail from, so this is an honest unsupported, not a skip.
        return ClaimSupport(sentence, cited, None, 0.0, 0.0, False)
    best = max(range(len(predictions)), key=lambda i: predictions[i][1])
    contradiction, entailment, _neutral = predictions[best]
    return ClaimSupport(
        sentence=sentence,
        cited=cited,
        best_ref=refs[best],
        entailment=entailment,
        contradiction=contradiction,
        supported=entailment >= threshold,
    )


@lru_cache(maxsize=1)
def _load_nli() -> NLI:
    """Load the real cross-encoder once per process, on CUDA when one is present.

    Imported lazily — see the module docstring — so a missing ``eval`` group fails
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
    model_name = os.environ.get(_ENV_MODEL) or DEFAULT_MODEL
    device = "cuda" if torch.cuda.is_available() else "cpu"
    return _CrossEncoderNLI(CrossEncoder(model_name, device=device))


class _CrossEncoderNLI:
    """Adapts a ``sentence_transformers.CrossEncoder`` NLI checkpoint to :class:`NLI`.

    ``cross-encoder/nli-deberta-v3-base`` (and the other ``cross-encoder/nli-*``
    checkpoints) emit raw logits in ``(contradiction, entailment, neutral)`` order —
    the model card's own convention. ``apply_softmax=True`` asks the library itself to
    turn those into the probabilities :class:`ClaimSupport` documents, rather than this
    module re-deriving softmax over an axis it would have to get right by inspection.
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
