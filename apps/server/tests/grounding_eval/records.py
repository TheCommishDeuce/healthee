"""One run's record, and the JSON file two arms are compared from.

The file is the unit of comparison because the two arms are two checkouts of the code,
not two settings inside it (see the package docstring). Everything needed to re-read a
result months later is stored with it: the git commit, the question set's own fingerprint,
and the timestamp — a comparison of two runs whose question sets differ is not a
comparison, and ``compare`` refuses it rather than printing a number that looks fine.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

from tests.grounding_eval.questions import EvalQuestion

# What happened to one question, at the grain that decides whether the owner saw anything.
GROUNDED = "grounded"  # validated text shipped
FALLBACK = "fallback"  # failed its gates twice — paid twice, shipped the honest fallback
REFUSED = "refused"  # a refusal template or a hard output guardrail
ERROR = "error"  # the transport or the DB failed; NOT a grounding outcome


@dataclass(frozen=True)
class RunRecord:
    """One question, one repeat, one outcome — the row every statistic is computed from."""

    question_id: str
    kind: str
    surface: str
    repeat: int
    outcome: str
    success: bool
    # What the question asked the pipeline to do (``questions.ANSWER`` / ``REFUSAL``).
    # Stored rather than re-derived, so a ship rate can never quietly pool a refusal
    # floor into a quality rate if the question set is reorganised later.
    expect: str = "answer"
    citations: list[str] = field(default_factory=list)
    top_notes: list[str] = field(default_factory=list)
    # Every WARNING/ERROR the pipeline logged while answering this question — which is
    # where the validator's issues, the guardrail fires and the fallback reasons live.
    # Without it an arm could say a third of its answers never shipped but not WHY, and
    # #99's whole diagnosis had to be recovered by grepping a console log that the next
    # run would overwrite. A number with no cause attached is the same problem this
    # harness was built to fix, one level up. Defaulted so arms written before it exist
    # still load.
    warnings: list[str] = field(default_factory=list)
    llm_calls: int = 0
    tool_rounds: int = 0
    tools: list[str] = field(default_factory=list)
    # WHICH MODEL produced this record. Without it a report can only price by SURFACE,
    # which silently hardcodes "coach = the expensive tier" — an assumption that was true
    # until the coach moved tiers on 2026-08-03 and would have kept quoting the old rate
    # ever after. Defaulted so arms saved before this field still load; a report that
    # finds it empty says the figure is approximate rather than guessing.
    model: str = ""
    prompt_tokens: int = 0
    completion_tokens: int = 0
    reasoning_tokens: int = 0
    # The provider-counted prefix-cache hit share of ``prompt_tokens`` — see
    # ``meter.Meter.cached_prompt_tokens``. Defaulted so arms saved before it existed
    # still load, the same as every other counter here.
    cached_prompt_tokens: int = 0
    unmetered_calls: int = 0
    # Provider-BILLED dollars (``meter.Meter.cost``, from ``Usage.cost``) — independent
    # of ``report.py``'s published-rate estimate. 0.0 for arms recorded before this field
    # existed, same convention as every other counter here.
    cost: float = 0.0
    latency_ms: int = 0
    error: str = ""
    # The final text the pipeline returned — the validated answer, or the fallback/
    # refusal text as shipped, stored VERBATIM. Without it two arms can only be COUNTED
    # (outcome, citations, tokens) and never READ, which is the gap this field closes:
    # a person can now open a scored arm and see which sentences the model actually
    # wrote. Defaulted so arms saved before it existed still load.
    answer: str = ""
    # The weakest evidence grade behind the answer's citations, or "" if the answer
    # cited nothing gradeable — ``CoachResult.grade_floor`` / ``GroundedResult.grade_floor``
    # on the shipped result types, both ``str | None``.
    grade_floor: str = ""
    # Filled ONLY by ``python -m tests.grounding_eval score`` (never by ``run``, which
    # spends no extra money to compute these): how many of the answer's sentences carried
    # a checkable claim, how many of those cited something, and how many citations the
    # NLI scorer judged actually SUPPORTED by the cited note at ``support_threshold``.
    # Zero on every record until an arm has been through ``score`` — a scored arm is
    # always a NEW file, never the original (see ``__main__.py``'s ``score`` command).
    support_claims: int = 0
    support_cited: int = 0
    support_supported: int = 0
    support_threshold: float = 0.0
    # The unsupported claim SENTENCES, verbatim, so a person can read what failed
    # without re-running the model or the scorer.
    support_unsupported: list[str] = field(default_factory=list)
    support_model: str = ""
    # Every claim `score` scored, in full — one dict per `support.ClaimSupport`:
    # {sentence, fragments, cited, best_ref, best_fragment, entailment, contradiction,
    # supported, interpretive, scorable}. Without this an "unsupported" call can only be
    # trusted or re-run; with it, anybody can audit which fragment matched which passage
    # at what score, offline, from the saved arm alone. Defaulted so arms scored before
    # this field existed — and every unscored arm — still load with `[]`.
    support_details: list[dict] = field(default_factory=list)
    # How many of `support_cited`'s claims had literally nothing to test them against
    # (every cited note's passages were all heading-only, or it carried none) —
    # `support.ClaimSupport.scorable is False`. A rate computed as `support_supported /
    # support_cited` silently counts these as failures; the honest denominator is
    # `support_cited - support_unscorable`. Defaulted so arms scored before this field
    # existed still load, reading as "nothing was unscorable" rather than erroring —
    # which is wrong for THOSE arms but matches their own (unfixed) counting at the time.
    support_unscorable: int = 0


@dataclass(frozen=True)
class EvalRun:
    """A whole arm: its provenance plus every record in it."""

    label: str
    commit: str
    question_set: str
    repeats: int
    started_at: str
    records: list[RunRecord]


def question_set_fingerprint(questions: tuple[EvalQuestion, ...]) -> str:
    """A short hash of the exact question TEXTS — the premise a comparison rests on.

    Texts, not ids: renaming an id is cosmetic, editing a prompt is a different
    experiment wearing the same name.
    """
    blob = "\n".join(f"{q.id} {q.text} {q.expect}" for q in questions)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:12]


def git_commit() -> str:
    """The commit the arm ran at, or ``unknown`` — never a guess, never a crash."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    return out.stdout.strip() or "unknown"


def new_run(label: str, questions: tuple[EvalQuestion, ...], repeats: int) -> EvalRun:
    """An empty arm stamped with everything needed to interpret it later."""
    return EvalRun(
        label=label,
        commit=git_commit(),
        question_set=question_set_fingerprint(questions),
        repeats=repeats,
        started_at=datetime.now(tz=UTC).isoformat(timespec="seconds"),
        records=[],
    )


def save(run: EvalRun, path: Path) -> None:
    path.write_text(json.dumps(asdict(run), indent=2), encoding="utf-8")


def load(path: Path) -> EvalRun:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return EvalRun(
        label=raw["label"],
        commit=raw["commit"],
        question_set=raw["question_set"],
        repeats=raw["repeats"],
        started_at=raw["started_at"],
        records=[RunRecord(**r) for r in raw["records"]],
    )
