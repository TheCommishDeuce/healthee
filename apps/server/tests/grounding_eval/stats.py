"""The arithmetic — intervals, not point estimates, and a paired test with a p value.

This module is the reason the harness can be believed. Every rate it produces carries a
95% Wilson interval, and a comparison between two arms is a PAIRED test (McNemar, exact
binomial on the discordant pairs) rather than two independent proportions: the arms ran
the same questions, and pairing is what makes a small n say anything at all.

Wilson rather than the textbook normal interval because n here is tens, not thousands,
and the rates sit near the ends — the normal interval famously produces (1.0, 1.0) for
8/8 and can run below zero, which would let the harness claim certainty it has not
earned. Student's t rather than z for the token means for the same reason.

It is pure arithmetic over records: no network, no database, no model. That is why its
unit tests DO run in the normal suite while the harness itself never does.
"""

from __future__ import annotations

import math
import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from scipy.stats import binomtest, t
from tests.grounding_eval.records import ERROR, GROUNDED, RunRecord

Z95 = 1.959963984540054

# A validator/guard issue's CAUSE: a capitalised phrase before the colon that introduces
# the offending sentence, and only when it opens a quoted tuple element — so the log
# line's own "coach: candidate failed..." prefix (lowercase, unquoted) is not a cause.
_CAUSE_RE = re.compile(r"""(?:^|['"(])\s*([A-Z][A-Za-z/() -]{4,70}?):\s""")


def wilson(successes: int, n: int, z: float = Z95) -> tuple[float, float]:
    """The Wilson score interval for ``successes``/``n`` — (lo, hi), clamped to [0, 1].

    ``n == 0`` returns the whole interval: with no observations every rate is possible,
    which is the honest statement and not an error.
    """
    if n <= 0:
        return (0.0, 1.0)
    p = successes / n
    denom = 1.0 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


@dataclass(frozen=True)
class Rate:
    """A proportion that can never be quoted without its n and its interval."""

    label: str
    successes: int
    n: int

    @property
    def rate(self) -> float:
        return self.successes / self.n if self.n else 0.0

    @property
    def ci(self) -> tuple[float, float]:
        return wilson(self.successes, self.n)

    def line(self) -> str:
        lo, hi = self.ci
        return (
            f"{self.label:<18} {self.successes:>3}/{self.n:<3} = {self.rate:5.1%}  "
            f"[95% CI {lo:5.1%} – {hi:5.1%}]"
        )


def mean_ci(values: Sequence[float]) -> tuple[float, float, float]:
    """(mean, lo, hi) at 95% using Student's t — (0,0,0) for an empty sample.

    A single observation has a mean and no interval, so it reports (v, v, v): pretending
    otherwise would put an interval on a number that has none.
    """
    n = len(values)
    if n == 0:
        return (0.0, 0.0, 0.0)
    mean = sum(values) / n
    if n == 1:
        return (mean, mean, mean)
    sd = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1))
    half = float(t.ppf(0.975, n - 1)) * sd / math.sqrt(n)
    return (mean, mean - half, mean + half)


@dataclass(frozen=True)
class Paired:
    """The McNemar table for two arms over the same questions, plus its exact p.

    ``b`` = pairs the FIRST arm shipped and the second did not; ``c`` = the reverse.
    Concordant pairs carry no information about a difference and are counted only so the
    reader can see how much of the sample the test actually rests on.
    """

    pairs: int
    both: int
    neither: int
    b_only: int
    c_only: int
    p_value: float

    @property
    def significant(self) -> bool:
        return self.p_value < 0.05

    @property
    def verdict(self) -> str:
        if self.b_only == self.c_only:
            return "no difference at all in the paired outcomes"
        direction = "WORSE" if self.b_only > self.c_only else "BETTER"
        if not self.significant:
            return (
                f"{direction} on {abs(self.b_only - self.c_only)} net pair(s), "
                f"NOT significant at 95% (p={self.p_value:.3f}) — this is 'not measurably "
                "different', not 'the same'"
            )
        return f"{direction}, significant at 95% (p={self.p_value:.3f})"


def mcnemar(b_only: int, c_only: int) -> float:
    """Two-sided exact p for a McNemar table's discordant pairs.

    Exact binomial rather than the chi-square approximation: with a handful of discordant
    pairs the approximation is anti-conservative, and this harness exists precisely to
    stop small samples from sounding confident. No discordance at all ⇒ p = 1.0.
    """
    n = b_only + c_only
    if n == 0:
        return 1.0
    return float(binomtest(b_only, n, 0.5).pvalue)


def paired(first: Sequence[RunRecord], second: Sequence[RunRecord]) -> Paired:
    """Pair two arms on (question, repeat) and run McNemar over the shared pairs.

    Pairing on the repeat INDEX is not pairing on identical conditions — the model is
    stochastic and repeat 2 of an arm is not "the same trial" as repeat 2 of the other.
    What pairing buys is removal of the between-QUESTION variance, which dominates here
    (one question ships 8/8, another 1/8). Records present in only one arm are dropped.
    """
    left = {(r.question_id, r.repeat): r.success for r in scored(first)}
    right = {(r.question_id, r.repeat): r.success for r in scored(second)}
    shared = sorted(set(left) & set(right))
    both = sum(1 for k in shared if left[k] and right[k])
    neither = sum(1 for k in shared if not left[k] and not right[k])
    b_only = sum(1 for k in shared if left[k] and not right[k])
    c_only = sum(1 for k in shared if not left[k] and right[k])
    return Paired(
        pairs=len(shared),
        both=both,
        neither=neither,
        b_only=b_only,
        c_only=c_only,
        p_value=mcnemar(b_only, c_only),
    )


@dataclass(frozen=True)
class PairedMean:
    """A paired difference in a continuous measure (tokens, calls, latency)."""

    pairs: int
    baseline: float
    delta: float
    lo: float
    hi: float

    @property
    def pct(self) -> float:
        return self.delta / self.baseline if self.baseline else 0.0

    @property
    def significant(self) -> bool:
        """True when the 95% interval excludes zero — i.e. the sign is established."""
        return (self.lo > 0) or (self.hi < 0)

    def line(self, label: str) -> str:
        verdict = "sign established" if self.significant else "sign NOT established (CI spans 0)"
        return (
            f"{label:<22} {self.delta:+10.0f} ({self.pct:+.1%})  "
            f"[95% CI {self.lo:+.0f} – {self.hi:+.0f}]  n={self.pairs} pairs · {verdict}"
        )


def paired_delta(
    first: Sequence[RunRecord],
    second: Sequence[RunRecord],
    value: Callable[[RunRecord], float],
) -> PairedMean:
    """second − first for ``value``, PAIRED per (question, repeat).

    Two unpaired means with overlapping intervals say almost nothing here, because the
    between-question spread is enormous (35k tokens for a one-call knowledge question,
    340k for a seven-call compound one). Differencing within a pair removes it, which is
    the only way a ~15% cost change is visible at n in the tens.
    """
    left = {(r.question_id, r.repeat): r for r in scored(first)}
    right = {(r.question_id, r.repeat): r for r in scored(second)}
    shared = sorted(set(left) & set(right))
    deltas = [value(right[k]) - value(left[k]) for k in shared]
    baseline = sum(value(left[k]) for k in shared) / len(shared) if shared else 0.0
    delta, lo, hi = mean_ci(deltas)
    return PairedMean(pairs=len(shared), baseline=baseline, delta=delta, lo=lo, hi=hi)


def scored(records: Sequence[RunRecord]) -> list[RunRecord]:
    """Every record a rate may rest on — i.e. everything except transport/DB errors.

    An error is excluded from the DENOMINATOR rather than counted as a failure: a
    connection reset is not evidence about grounding, and folding it in would move the
    exact number this harness exists to protect. The count is reported separately, so an
    arm that errored half its questions cannot look like a clean small sample.
    """
    return [r for r in records if r.outcome != ERROR]


def answering(records: Sequence[RunRecord]) -> list[RunRecord]:
    """Only the scored records whose question expects an ANSWER — not the refusal floor."""
    return [r for r in scored(records) if r.expect == "answer"]


def errors(records: Sequence[RunRecord]) -> list[RunRecord]:
    return [r for r in records if r.outcome == ERROR]


def ship_rate(records: Sequence[RunRecord], label: str = "overall") -> Rate:
    """The headline: of the answers we paid for, how many reached the owner."""
    answers = answering(records)
    return Rate(label, sum(1 for r in answers if r.success), len(answers))


def rates_by_kind(records: Sequence[RunRecord]) -> list[Rate]:
    """Success rate per question kind — the safety floor included, labelled by its kind."""
    kinds = sorted({r.kind for r in records})
    out: list[Rate] = []
    for kind in kinds:
        subset = [r for r in scored(records) if r.kind == kind]
        out.append(Rate(kind, sum(1 for r in subset if r.success), len(subset)))
    return out


def failure_causes(records: Sequence[RunRecord]) -> list[tuple[str, int]]:
    """How often each distinct validator/guardrail cause appears, commonest first.

    A cause is the part of an issue BEFORE its quoted sentence ("Probable claim stated
    without a hedge"), so the same defect over twenty different sentences counts as one
    row of twenty rather than twenty rows of one. That grouping is the whole finding of
    #99: the causes are few and lexical, while the sentences are all different, and a
    report that printed the sentences would have hidden it.
    """
    counts: dict[str, int] = {}
    for record in records:
        for line in record.warnings:
            for cause in _causes_in(line):
                counts[cause] = counts.get(cause, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))


def _causes_in(line: str) -> list[str]:
    """The issue causes named in one captured log line, de-quoted and de-duplicated.

    The issues arrive inside a repr'd tuple, each shaped ``<Cause>: '<the sentence>'``.
    Matching the CAUSE (a capitalised phrase before a colon, opening a quoted element)
    rather than splitting the repr keeps this working whichever quote character the
    sentence's own apostrophes force Python to choose.
    """
    if "OUTPUT GUARDRAIL fired" in line:
        return ["hard output guardrail"]
    # "failed the gates …" — the tail moved when the retry budget stopped being fixed at
    # one ("twice" → "on every attempt"), so the match is on the stable half. Arms saved
    # before that change still carry the old sentence and still parse, which is the point:
    # a census that could not read last month's arm cannot compare against it.
    if "failed the gates" not in line:
        return []
    return sorted(set(_CAUSE_RE.findall(line)))


def rates_by_question(records: Sequence[RunRecord]) -> list[Rate]:
    """Per-question success — where a single bad surface hides inside a decent average."""
    rows = scored(records)
    ids = sorted({r.question_id for r in rows})
    return [
        Rate(qid, sum(1 for r in rows if r.question_id == qid and r.success), c)
        for qid in ids
        if (c := sum(1 for r in rows if r.question_id == qid))
    ]


def p95(values: Sequence[float]) -> float:
    """The 95th percentile, nearest-rank — 0.0 for an empty sample.

    Speed is one of the two things an arm comparison exists to settle, and a mean alone
    hides the tail an owner actually notices — one seven-round compound question can sit
    far above everything else without moving the mean much at all.
    """
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, math.ceil(0.95 * len(ordered)) - 1)
    return ordered[index]


# ── citation SUPPORT (filled by `score`, never by `run`) ─────────────────────────────
# A record's ``support_threshold`` is 0.0 until `score` sets it, and `score` only ever
# sets it on a GROUNDED record with an answer — so "any record with support_threshold >
# 0" is exactly "this arm has been scored" and "this record was scored" at once. That is
# why every function below filters on it rather than on a separate scored/unscored flag:
# a second flag could disagree with the data, this cannot.


def support_records(records: Sequence[RunRecord]) -> list[RunRecord]:
    """The grounded, scored records every support metric is computed from."""
    return [r for r in scored(records) if r.outcome == GROUNDED and r.support_threshold > 0]


def is_scored(records: Sequence[RunRecord]) -> bool:
    """Whether ANY record in this arm has been through ``score`` — gates the support lines.

    An arm nobody scored must print nothing new: a support section full of zeros would
    read as "every claim failed" rather than "nobody asked the question".
    """
    return any(r.support_threshold > 0 for r in records)


def supported_citation_rate(records: Sequence[RunRecord]) -> Rate:
    """Of the citations a scored answer actually used, how many the NLI judged supported.

    The denominator EXCLUDES unscorable claims (``support_unscorable``) — a claim with
    literally nothing to test it against (every cited note's passages heading-only, or
    none at all) is not evidence the model rejected, and counting it in the denominator
    would silently read "we never asked" as "the answer failed". See
    :func:`unscorable_claim_count` for the count printed alongside this rate.
    """
    rows = support_records(records)
    cited = sum(r.support_cited for r in rows)
    unscorable = sum(r.support_unscorable for r in rows)
    return Rate("supported citations", sum(r.support_supported for r in rows), cited - unscorable)


def unscorable_claim_count(records: Sequence[RunRecord]) -> int:
    """How many cited claims across this arm had nothing to test them against at all."""
    return sum(r.support_unscorable for r in support_records(records))


def cited_claim_rate(records: Sequence[RunRecord]) -> Rate:
    """Of the checkable claims a scored answer made, how many carried a citation at all."""
    rows = support_records(records)
    return Rate(
        "cited claims", sum(r.support_cited for r in rows), sum(r.support_claims for r in rows)
    )


def supported_fraction(record: RunRecord) -> float:
    """One record's supported/cited fraction — 0.0 when it cited nothing to support.

    The value :func:`paired_delta` differences per (question, repeat) to say whether a
    retrieval change moved SUPPORT, not just whether it moved the ship rate.
    """
    return record.support_supported / record.support_cited if record.support_cited else 0.0
