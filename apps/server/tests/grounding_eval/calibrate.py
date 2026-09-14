"""The human-labelling loop the SUPPORT scorer needs before its verdicts are trusted.

``support.py`` scores every cited claim against an NLI cross-encoder it never asked a
human to check. ``docs/HOW_WE_VERIFY.md`` section 2 is about exactly this kind of gap:
a green number that has never been tested against ground truth is a belief, not a
measurement. This module closes that gap cheaply — no paid LLM call, no re-run of the
arm — by sampling claims a v2-scored arm already produced, handing a human a sheet with
the evidence already surfaced, and turning their yes/no labels into precision/recall/F1
at a handful of thresholds.

    uv run python -m tests.grounding_eval calibrate baseline.v2.scored.json \\
        --sample 40 --out sheet.json --seed 1
    # ... a human fills in "label": true|false on each row of sheet.json ...
    uv run python -m tests.grounding_eval calibrate --labels sheet.json --report
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path

from tests.grounding_eval import support
from tests.grounding_eval.records import EvalRun

DEFAULT_THRESHOLDS: tuple[float, ...] = (0.3, 0.4, 0.5, 0.6, 0.7)


def sample(run: EvalRun, *, n: int, seed: int, nli: support.NLI | None = None) -> list[dict]:
    """A stratified (half currently-supported, half not), seeded sample of ``n`` claims.

    Seeded so the SAME arm + seed always produces the SAME sheet — a re-run must be
    able to reproduce exactly what a human already labelled, not draw a fresh set
    that silently orphans their work. A group short of its half draws everything it
    has rather than raising: a small arm should shrink the sheet, not block it.

    ``nli`` is injectable so a unit test can sample without the real model; ``score``
    and the CLI leave it unset and get the configured checkpoint (see `support.py`).
    """
    claims = _cited_claims(run)
    supported = [c for c in claims if c["supported"]]
    unsupported = [c for c in claims if not c["supported"]]
    rng = random.Random(seed)
    half = n // 2
    picked = _draw(rng, supported, half) + _draw(rng, unsupported, n - half)
    rng.shuffle(picked)
    return [_sheet_row(claim, nli) for claim in picked]


def _cited_claims(run: EvalRun) -> list[dict]:
    """Every cited claim across every scored record, tagged with where it came from.

    Reads ``RunRecord.support_details`` — the exact rows ``score`` wrote — so sampling
    never re-derives a claim's fragments or citations a second, possibly divergent, way.
    The ``detail.get("cited")`` filter is defensive: every row `score` writes already
    has a non-empty ``cited`` (claim SELECTION in `support.py` requires it), so no
    fixture here exercises the filter actually dropping a row — kept for a hand-edited
    or future-shaped sheet, not for data this pipeline can itself produce.
    """
    return [
        {**detail, "question_id": record.question_id, "repeat": record.repeat}
        for record in run.records
        for detail in record.support_details
        if detail.get("cited")
    ]


def _draw(rng: random.Random, population: list[dict], k: int) -> list[dict]:
    return rng.sample(population, min(k, len(population)))


def _sheet_row(claim: dict, nli: support.NLI | None) -> dict:
    """One sampled claim, PLUS the top-3 passages by entailment — the evidence a human
    needs to judge it without re-running anything themselves."""
    top_passages = support.rank_passages(
        claim["sentence"], claim["cited"], claim["fragments"] or [claim["sentence"]], nli=nli
    )
    return {
        "question_id": claim["question_id"],
        "repeat": claim["repeat"],
        "sentence": claim["sentence"],
        "cited": claim["cited"],
        "fragments": claim["fragments"],
        "currently_supported": claim["supported"],
        "entailment": claim["entailment"],
        "top_passages": top_passages,
        "label": None,
    }


def write_sheet(rows: list[dict], path: Path) -> None:
    path.write_text(json.dumps(rows, indent=2), encoding="utf-8")


def load_sheet(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


@dataclass(frozen=True)
class Threshold:
    """Precision / recall / F1 for one entailment cutoff, plus the counts behind them."""

    t: float
    tp: int
    fp: int
    fn: int
    tn: int

    @property
    def precision(self) -> float:
        return self.tp / (self.tp + self.fp) if (self.tp + self.fp) else 0.0

    @property
    def recall(self) -> float:
        return self.tp / (self.tp + self.fn) if (self.tp + self.fn) else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 2 * p * r / (p + r) if (p + r) else 0.0

    def line(self) -> str:
        return (
            f"  t={self.t:.1f}  precision {self.precision:.3f}  recall {self.recall:.3f}  "
            f"f1 {self.f1:.3f}  (tp={self.tp} fp={self.fp} fn={self.fn} tn={self.tn})"
        )


def evaluate(
    labels: list[dict],
    *,
    thresholds: tuple[float, ...] = DEFAULT_THRESHOLDS,
    nli: support.NLI | None = None,
) -> list[Threshold]:
    """One :class:`Threshold` per cutoff, scored against the human ``label`` field.

    Uses each claim's already-recorded ``entailment`` unless ``nli`` is given, in which
    case every labelled claim is re-scored against it first — how ``--model`` prices a
    second checkpoint's numbers without a second paid arm.
    """
    labelled = [row for row in labels if row.get("label") is not None]
    scores = [
        (_rescore(row, nli) if nli is not None else row["entailment"], bool(row["label"]))
        for row in labelled
    ]
    return [_at_threshold(t, scores) for t in thresholds]


def report(
    labels: list[dict],
    *,
    thresholds: tuple[float, ...] = DEFAULT_THRESHOLDS,
    nli: support.NLI | None = None,
) -> str:
    """Precision / recall / F1 at each threshold, formatted for a terminal."""
    n_labelled = sum(1 for row in labels if row.get("label") is not None)
    lines = [f"n labelled = {n_labelled} (of {len(labels)} sampled)"]
    lines += [t.line() for t in evaluate(labels, thresholds=thresholds, nli=nli)]
    return "\n".join(lines)


def _rescore(claim: dict, nli: support.NLI) -> float:
    """Re-run ``nli`` over this claim's recorded fragments x its top-3 recorded passages.

    Limited to those top-3 rather than every passage of every cited note: cheap, and
    good enough to calibrate a threshold, but the true best passage for a DIFFERENT
    model is not guaranteed to be among them — a known gap for a wholesale model swap,
    not for choosing a threshold on the model already in use.
    """
    fragments = claim.get("fragments") or [claim["sentence"]]
    pairs = [(p["text"], fragment) for p in claim.get("top_passages", []) for fragment in fragments]
    if not pairs:
        return 0.0
    predictions = nli.predict(pairs)
    return max(entailment for _contradiction, entailment, _neutral in predictions)


def _at_threshold(t: float, scores: list[tuple[float, bool]]) -> Threshold:
    tp = sum(1 for s, y in scores if s >= t and y)
    fp = sum(1 for s, y in scores if s >= t and not y)
    fn = sum(1 for s, y in scores if s < t and y)
    tn = sum(1 for s, y in scores if s < t and not y)
    return Threshold(t, tp, fp, fn, tn)
