"""Turn records into text a person can act on — n and uncertainty on every line.

Nothing here computes; it prints what ``stats`` computed. The rule the format enforces
is that a rate NEVER appears without its n and its 95% interval, and a comparison never
appears without its p value and an explicit sentence about significance. A number in
this output that is not measured (the money figure) says which assumption it rests on.
"""

from __future__ import annotations

from collections.abc import Sequence

from tests.grounding_eval import stats
from tests.grounding_eval.records import EvalRun, RunRecord

# Published OpenRouter rates, (input, output) USD per MILLION tokens, read 2026-08-03.
#
# ## Why one flat rate could not do this
#
# This priced every record at $0.50/$3.00. The models we actually run are 17x apart on
# input, so a single rate was wrong in BOTH directions at once — it understated a
# gemini-3.6-flash coach record ~2.9x while overstating a flash-lite record ~1.67x. Two
# runs measured on 2026-08-03 cost $8.22 and $0.43; it printed $2.80 and $2.52, i.e. it
# reported a 19x difference as no difference at all. Numbers from this report are pasted
# into INTELLIGENCE.md §9 and read months later as the record of what an experiment cost.
#
# ## Why by MODEL and not by surface
#
# The obvious fix is to price by `surface` — coach vs grounded. That hardcodes "the coach
# runs the expensive tier", which was true until the coach moved tiers on 2026-08-03 and
# would then have quoted the old rate forever, silently. `RunRecord.model` records what
# actually ran, so the rate follows the evidence rather than an assumption about it.
#
# Output is billed on tokens produced INCLUDING the reasoning a reasoning model spends
# invisibly — which is not a footnote: gemini-3.6-flash spends ~85% of its output there,
# billed at $7.50/M and never shown to anyone. That is why the reasoning share is printed
# rather than folded away.
_RATES: dict[str, tuple[float, float]] = {
    "google/gemini-3.6-flash": (1.50, 7.50),
    "google/gemini-3.5-flash-lite": (0.30, 2.50),
    "deepseek/deepseek-v4-flash-0731": (0.09, 0.18),
    # The coach's CURRENT model (reference_coach_model_bakeoff, 2026-09-10) — read from
    # OpenRouter's public models endpoint 2026-09-14. Without an entry every coach record
    # in an arm taken after that switch prices at the dearest FALLBACK rate below, which
    # reads the run as more expensive than it is, not less — but still wrong either way.
    "deepseek/deepseek-v4.1-flash": (0.30, 1.20),
}

# What an UNKNOWN model bills at. Deliberately the dearest rate we know: an unpriced model
# should make a run look too expensive, never too cheap. A cost that reads high gets
# questioned; one that reads low gets budgeted against.
_FALLBACK_RATE = max(_RATES.values())

# Arms saved before `RunRecord.model` existed (< 2026-08-03) carry "". Their coach records
# ran google/gemini-3.6-flash and their grounded records google/gemini-3.5-flash-lite —
# the configuration of that period. `cost_is_exact` reports whether any record needed this
# guess, so an old arm's figure is labelled approximate instead of quietly asserted.
_LEGACY_BY_SURFACE = {"coach": "google/gemini-3.6-flash"}
_LEGACY_DEFAULT = "google/gemini-3.5-flash-lite"


def rate_for(record: RunRecord) -> tuple[float, float]:
    """(input, output) USD per M for whatever model produced ``record``."""
    model = record.model or _LEGACY_BY_SURFACE.get(record.surface, _LEGACY_DEFAULT)
    return _RATES.get(model, _FALLBACK_RATE)


def cost_is_exact(records: Sequence[RunRecord]) -> bool:
    """False when any record was priced by a guess — an unrecorded model or an unknown one."""
    return all(r.model and r.model in _RATES for r in records)


def _cost_usd(records: Sequence[RunRecord]) -> float:
    total = 0.0
    for r in records:
        rate_in, rate_out = rate_for(r)
        total += r.prompt_tokens / 1e6 * rate_in + r.completion_tokens / 1e6 * rate_out
    return total


def _mean_line(label: str, values: Sequence[float], unit: str = "") -> str:
    mean, lo, hi = stats.mean_ci(values)
    return f"{label:<28} {mean:9.1f}{unit}  [95% CI {lo:.1f} – {hi:.1f}]  n={len(values)}"


def _support_lines(records: Sequence[RunRecord]) -> list[str]:
    """The CITATION SUPPORT block's body — split out of :func:`summary` to keep its
    own mccabe complexity under the gate."""
    lines = [
        "  " + stats.supported_citation_rate(records).line(),
        "  " + stats.cited_claim_rate(records).line(),
        "  "
        + _mean_line(
            "supported claims / answer",
            [float(r.support_supported) for r in stats.support_records(records)],
        ),
    ]
    unscorable = stats.unscorable_claim_count(records)
    if unscorable:
        lines.append(
            f"  ⚠ {unscorable} cited claim(s) UNSCORABLE (no non-heading passage to test "
            "against) — excluded from the rate above, not counted as unsupported"
        )
    return lines


def summary(run: EvalRun) -> str:
    """The whole arm in one block: rates with intervals, spend, and the weak spots."""
    records = run.records
    ok = stats.scored(records)
    answers = stats.answering(records)
    lines = [
        f"── {run.label} ── commit {run.commit} · set {run.question_set} · "
        f"{run.repeats} repeat(s) · {run.started_at}",
        "",
        "SHIP RATE (the owner saw an answer we paid for)",
        "  " + stats.ship_rate(records).line(),
        "",
        "by kind",
    ]
    lines += ["  " + rate.line() for rate in stats.rates_by_kind(records)]
    lines += ["", "by question"]
    lines += ["  " + rate.line() for rate in stats.rates_by_question(records)]
    lines += ["", "OUTCOMES"]
    for outcome in sorted({r.outcome for r in records}):
        lines.append(f"  {outcome:<10} {sum(1 for r in records if r.outcome == outcome):>3}")
    shipped_citations = [len(r.citations) for r in answers if r.success]
    coach_rounds = [r.tool_rounds for r in ok if r.surface == "coach"]
    lines += ["", "PER QUESTION (means over every scored run)"]
    lines += [
        "  " + _mean_line("citations / shipped answer", shipped_citations),
        "  " + _mean_line("llm calls", [r.llm_calls for r in ok]),
        "  " + _mean_line("tool rounds (coach)", coach_rounds),
        "  " + _mean_line("input tokens", [r.prompt_tokens for r in ok]),
        "  " + _mean_line("output tokens (incl. reasoning)", [r.completion_tokens for r in ok]),
        "  " + _mean_line("reasoning tokens", [r.reasoning_tokens for r in ok]),
        "  " + _mean_line("latency", [r.latency_ms for r in ok], " ms"),
    ]
    lines += ["", "LATENCY BY SURFACE (mean and p95 — speed is half of what an arm is judged on)"]
    for surface in sorted({r.surface for r in ok}):
        by_surface = [float(r.latency_ms) for r in ok if r.surface == surface]
        mean, lo, hi = stats.mean_ci(by_surface)
        lines.append(
            f"  {surface:<10} mean {mean:7.0f} ms  [95% CI {lo:.0f} – {hi:.0f}]  "
            f"p95 {stats.p95(by_surface):7.0f} ms  n={len(by_surface)}"
        )
    lines += ["", "PROMPT CACHE HIT BY SURFACE (provider-counted; a miss re-reads the corpus)"]
    for surface in sorted({r.surface for r in ok}):
        by_surface = [r for r in ok if r.surface == surface]
        prompt_total = sum(r.prompt_tokens for r in by_surface)
        cached_total = sum(r.cached_prompt_tokens for r in by_surface)
        # A plain share, NOT a `Rate`: tokens are not Bernoulli trials, so a Wilson
        # interval over them would print a "95% CI" that means nothing. The uncertainty
        # that IS meaningful — how much cache a question gets — is the mean line's.
        share = cached_total / prompt_total if prompt_total else 0.0
        lines.append(
            f"  {surface:<10} {cached_total:>9,} / {prompt_total:<9,} tokens = {share:5.1%}  · "
            + _mean_line(
                "cached tokens / question", [float(r.cached_prompt_tokens) for r in by_surface]
            )
        )
    if stats.is_scored(records):
        lines += ["", "CITATION SUPPORT (scored answers only — `score` re-checked each claim)"]
        lines += _support_lines(records)
    models = sorted({r.model for r in records if r.model})
    exact = cost_is_exact(records)
    header = "SPEND (measured tokens × each model's published rate)"
    if not exact:
        header += "  ⚠ APPROXIMATE — a record carried no model id, or an unknown one"
    lines += ["", header]
    lines += [
        f"  input {sum(r.prompt_tokens for r in records):,} tok · "
        f"output {sum(r.completion_tokens for r in records):,} tok "
        f"(of which {sum(r.reasoning_tokens for r in records):,} reasoning) "
        f"⇒ ${_cost_usd(records):.2f} for this run",
    ]
    if models:
        lines += ["  models: " + " · ".join(models)]
    causes = stats.failure_causes(records)
    if causes:
        lines += ["", "WHY ANSWERS DID NOT SHIP (issue causes, commonest first)"]
        lines += [f"  {count:>3}  {cause}" for cause, count in causes]
    unmetered = sum(r.unmetered_calls for r in records)
    if unmetered:
        lines.append(f"  ⚠ {unmetered} call(s) reported NO usage — spend is a lower bound")
    errored = stats.errors(records)
    if errored:
        lines += ["", f"⚠ {len(errored)} ERROR record(s), excluded from every rate above:"]
        lines += [f"  {r.question_id}#{r.repeat}: {r.error}" for r in errored[:10]]
    return "\n".join(lines)


def comparison(first: EvalRun, second: EvalRun) -> str:
    """Two arms, paired on (question, repeat) — with the p value and a plain verdict."""
    lines = [
        f"── {first.label} ({first.commit})  →  {second.label} ({second.commit})",
        "",
    ]
    if first.question_set != second.question_set:
        lines.append(
            "⚠ THE QUESTION SETS DIFFER "
            f"({first.question_set} vs {second.question_set}) — these two runs are not "
            "comparable; re-run both arms on one set."
        )
        return "\n".join(lines)
    a_rate, b_rate = (
        stats.ship_rate(first.records, "before"),
        stats.ship_rate(second.records, "after"),
    )
    test = stats.paired(first.records, second.records)
    lines += [
        "SHIP RATE",
        "  " + a_rate.line(),
        "  " + b_rate.line(),
        "",
        "PAIRED TEST (McNemar, exact two-sided binomial on the discordant pairs)",
        f"  {test.pairs} pair(s): both shipped {test.both} · neither {test.neither} · "
        f"only before {test.b_only} · only after {test.c_only}",
        f"  ⇒ {test.verdict}",
        "",
        "BY KIND (before → after)",
    ]
    before_kinds = {r.label: r for r in stats.rates_by_kind(first.records)}
    for after in stats.rates_by_kind(second.records):
        before = before_kinds.get(after.label)
        shown = f"{before.successes}/{before.n}" if before else "—"
        lines.append(
            f"  {after.label:<18} {shown:>7} → {after.successes}/{after.n}"
            f"   (after: {after.rate:5.1%} [{after.ci[0]:.0%}–{after.ci[1]:.0%}])"
        )
    lines += ["", "COST PER RUN"]
    for run in (first, second):
        ok = stats.scored(run.records)
        mean, lo, hi = stats.mean_ci([r.prompt_tokens for r in ok])
        lines.append(
            f"  {run.label:<10} input {sum(r.prompt_tokens for r in run.records):>9,} tok · "
            f"mean/question {mean:7.0f} [{lo:.0f}–{hi:.0f}] · ${_cost_usd(run.records):.2f}"
        )
    lines += ["", "PAIRED per-question deltas (after − before; the unpaired means above overlap"]
    lines += ["by construction — between-question spread dwarfs the effect)"]
    for label, value in (
        ("input tokens", lambda r: float(r.prompt_tokens)),
        ("output tokens", lambda r: float(r.completion_tokens)),
        ("cached prompt tokens", lambda r: float(r.cached_prompt_tokens)),
        ("llm calls", lambda r: float(r.llm_calls)),
        ("tool rounds", lambda r: float(r.tool_rounds)),
        ("citations", lambda r: float(len(r.citations))),
    ):
        lines.append("  " + stats.paired_delta(first.records, second.records, value).line(label))
    if stats.is_scored(first.records) and stats.is_scored(second.records):
        support_delta = stats.paired_delta(
            stats.support_records(first.records),
            stats.support_records(second.records),
            stats.supported_fraction,
        )
        lines += ["", "PAIRED citation-support delta (scored answers only, after − before)"]
        lines.append("  " + _fraction_delta_line("supported-citation fraction", support_delta))
    return "\n".join(lines)


def _fraction_delta_line(label: str, delta: stats.PairedMean) -> str:
    """Like ``PairedMean.line()`` but for a 0–1 fraction, where ``:+.0f`` would print 0.

    A rate never appears without n and its interval — same rule, formatted for a
    proportion instead of a token count.
    """
    verdict = "sign established" if delta.significant else "sign NOT established (CI spans 0)"
    return (
        f"{label:<28} {delta.delta:+.1%}  [95% CI {delta.lo:+.1%} – {delta.hi:+.1%}]  "
        f"n={delta.pairs} pairs · {verdict}"
    )
