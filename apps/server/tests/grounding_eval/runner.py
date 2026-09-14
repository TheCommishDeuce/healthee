"""Execute one arm: seed the throwaway owner, ask every question, record what happened.

Every question goes through the SHIPPED entry points (``run_coach`` / ``grounded_ask``)
with a metered client injected — the same seam the tests use for a stub. Nothing about
the pipeline is reconfigured for the eval, because a harness that measures a special
path measures nothing.

Two deliberate choices:

  * ``grounded_ask`` is called directly rather than through ``surfaces.sleep_insight``,
    so the per-day ``kv`` cache cannot serve repeat 2 the answer from repeat 1. Every
    repeat is a real generation, which is the only way a rate means anything.
  * a transport or database failure is recorded as ``ERROR`` and the run CONTINUES, but
    error records are never counted as either success or failure — a network blip is not
    evidence about grounding, and silently folding it into the denominator would bias
    exactly the number this harness exists to protect.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Iterator
from types import TracebackType
from uuid import UUID

from tests.contracts import seed
from tests.grounding_eval.meter import MeteredClient
from tests.grounding_eval.questions import REFUSAL, EvalQuestion
from tests.grounding_eval.records import ERROR, FALLBACK, GROUNDED, REFUSED, EvalRun, RunRecord

from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.insights.client import coach_model, default_model, get_client
from healthee.insights.coach import CoachResult, run_coach
from healthee.insights.grounded import GroundedResult, grounded_ask
from healthee.insights.retrieval import DEFAULT_TOP_N, rank_notes


def seed_owner() -> tuple[UUID, str]:
    """Reset + seed the contract dataset and return the owner every question runs as."""
    seed.reset()
    seed.seed_all()
    return SENTINEL_USER_ID, SENTINEL_TZ


def run_questions(
    run: EvalRun, questions: tuple[EvalQuestion, ...], repeats: int
) -> Iterator[RunRecord]:
    """Yield one record per (question, repeat), in a fixed order, appending to ``run``.

    A generator so a long paid run prints progress as it goes: a harness that only speaks
    at the end is a harness nobody interrupts when the first ten answers are all errors.
    """
    user_id, tz = seed_owner()
    client = MeteredClient(get_client())
    for repeat in range(repeats):
        for question in questions:
            record = _run_one(question, repeat, user_id, tz, client)
            run.records.append(record)
            yield record


class _CaptureWarnings(logging.Handler):
    """Collect the insights layer's WARNING+ lines for the duration of one question.

    A context manager on the ``healthee.insights`` logger rather than a new return value
    threaded through ``GroundedResult`` and ``CoachResult``: the harness OBSERVES, and a
    field added to a shipped result type for a test's benefit is a second reason for that
    type to change. It attaches and detaches around each question, so nothing leaks into
    the next one and the production logging path is untouched.
    """

    def __init__(self) -> None:
        super().__init__(level=logging.WARNING)
        self.lines: list[str] = []
        self._logger = logging.getLogger("healthee.insights")

    def emit(self, record: logging.LogRecord) -> None:
        self.lines.append(record.getMessage())

    def __enter__(self) -> _CaptureWarnings:
        self._logger.addHandler(self)
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self._logger.removeHandler(self)


def _run_one(
    question: EvalQuestion, repeat: int, user_id: UUID, tz: str, client: MeteredClient
) -> RunRecord:
    """One question, once — timed, metered, and classified into a single outcome."""
    client.reset()
    started = time.perf_counter()
    with _CaptureWarnings() as captured:
        try:
            outcome, citations, tools, answer, grade_floor = _ask(question, user_id, tz, client)
            error = ""
        except Exception as exc:  # noqa: BLE001 — one failure must not end a paid run
            outcome, citations, tools, answer, grade_floor = ERROR, [], [], "", ""
            error = f"{type(exc).__name__}: {exc}"
    elapsed_ms = int((time.perf_counter() - started) * 1000)
    meter = client.meter
    return RunRecord(
        question_id=question.id,
        kind=question.kind,
        surface=question.surface,
        model=(coach_model() if question.surface == "coach" else default_model()),
        repeat=repeat,
        outcome=outcome,
        success=_is_success(question, outcome),
        expect=question.expect,
        citations=citations,
        top_notes=[n.id for n in rank_notes(question.text, question.metrics)[:DEFAULT_TOP_N]],
        llm_calls=meter.llm_calls,
        tool_rounds=meter.tool_rounds,
        tools=tools,
        prompt_tokens=meter.prompt_tokens,
        completion_tokens=meter.completion_tokens,
        reasoning_tokens=meter.reasoning_tokens,
        cached_prompt_tokens=meter.cached_prompt_tokens,
        unmetered_calls=meter.unmetered_calls,
        latency_ms=elapsed_ms,
        error=error,
        warnings=captured.lines,
        answer=answer,
        grade_floor=grade_floor,
    )


def _ask(
    question: EvalQuestion, user_id: UUID, tz: str, client: MeteredClient
) -> tuple[str, list[str], list[str], str, str]:
    """Run one question on its real surface → (outcome, citations, tools, answer, grade_floor).

    ``answer`` is the verbatim final text the pipeline returned — ``CoachResult.reply``
    on the coach surface, ``GroundedResult.text`` on the non-conversational one — so a
    saved arm can be READ later, not only counted. ``grade_floor`` is ``result.grade_floor
    or ""``: both result types carry it as ``str | None``.
    """
    if question.surface == "coach":
        result = run_coach([{"role": "user", "content": question.text}], user_id, tz, client=client)
        return (
            _outcome(result),
            list(result.citations),
            [call["tool"] for call in result.tool_calls],
            result.reply,
            result.grade_floor or "",
        )
    grounded = grounded_ask(
        question.text,
        user_id,
        tz,
        metrics=list(question.metrics),
        context_days=question.context_days,
        response_format=question.response_format,
        client=client,
    )
    return (
        _outcome(grounded),
        list(grounded.citations),
        [],
        grounded.text,
        grounded.grade_floor or "",
    )


def _outcome(result: CoachResult | GroundedResult) -> str:
    """The one classification every statistic rests on.

    ``refused`` covers both a pre-LLM refusal template and a hard output guardrail — from
    the owner's side they are the same event (a deliberate non-answer), and both are
    correct outcomes for a safety question and wrong ones for any other.
    """
    if result.refused:
        return REFUSED
    return GROUNDED if result.validated else FALLBACK


def _is_success(question: EvalQuestion, outcome: str) -> bool:
    """Success is measured against what the question ASKED the pipeline to do."""
    if outcome == ERROR:
        return False
    if question.expect == REFUSAL:
        return outcome == REFUSED
    return outcome == GROUNDED
