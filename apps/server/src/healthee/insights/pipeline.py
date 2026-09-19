"""The choke point's STAGES — the one body both LLM surfaces run (INTELLIGENCE §3).

Until this module existed the coach was *enforced-equivalent* to the choke point rather
than *routed through* it: ``grounded.py`` and ``coach.py` each called the primitives
(``classify_refusal``, ``check_output``, ``validate``, the honest fallback) in their own
order, from their own loop. The rule that followed — "every rule added to the choke point
must be mirrored in the coach" — was enforced by a human remembering, and it had already
been missed once: the hard output guardrail had to be written in two places.

The split existed for a real reason: the coach needs a bounded TOOL LOOP and
``grounded_ask`` does not. So the fork was moved rather than removed. Everything the two
surfaces share lives here as one code path; the only difference either surface expresses
is *how one model turn is produced* (:class:`Turn`) and *how its messages are laid out*.

Stage order, and where each one now lives:

  1. question gate ......... :func:`check_question`  (``refusals.classify_refusal``)
  2. context ............... :func:`user_context`    (``context.build_context``)
  3. retrieval ............. :func:`evidence`        (``retrieval.evidence_section``)
  4. LLM turn .............. :func:`complete`        (the ONE transport call)
  5. hard output guardrail . ``_output_guard_gate``  — BLOCKING, never retried
  6. blocking validator .... ``_validator_gate``     — prose or JSON
  7. anti-hallucination .... ``_action_claim_gate``  — an action claim needs a tool
  8. answer shape .......... ``_structure_gate``     — a structured surface's own contract
  9. personal claims ....... ``_personal_claim_gate``— a value asserted for data we lack
 10. gather → answer → nudge → fallback ... :func:`drive` — unvalidated text NEVER ships

Stages 5–9 are a REGISTRY (:func:`answer_gates`), not a hardcoded sequence, and stage 1
is one too (:func:`question_gates`). That is what makes the acceptance bar mechanical: a
stage added to a registry reaches every surface by construction, and
``tests/insights/test_pipeline_shared.py`` proves it by injecting one and asserting BOTH
surfaces obey it. Its companion — an AST guard in the same file — asserts that no module
except this one reaches a primitive directly, so a stage cannot be re-added to one side
only without failing a test.

Stage 5 runs BEFORE stage 6 on purpose: a forbidden output is not a grounding problem to
nudge the model out of, it is a floor (INTELLIGENCE §3, ``output_guard``'s docstring).
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from uuid import UUID

from healthee.core.logging import get_logger
from healthee.insights import prompts
from healthee.insights.action_claims import claim_issues
from healthee.insights.budgets import (
    _Progress,
    gathering_deadline_s,
    turn_budget,
    validation_retries,
)
from healthee.insights.client import ChatResponse, LLMClient
from healthee.insights.context import build_context
from healthee.insights.evidence import build_evidence

# The gate vocabulary is re-exported: ``pipeline.AnswerContext`` / ``pipeline.GateOutcome``
# stay what every caller and test writes. It lives in its own module only so a gate whose
# subject matter has one (``personal_claims``) can name these types without a cycle.
from healthee.insights.gate_types import AnswerContext, AnswerGate, Block, GateOutcome, Verdict
from healthee.insights.output_guard import check_output
from healthee.insights.personal_claims import issues as personal_claim_issues
from healthee.insights.refusals import Domain, classify_refusal
from healthee.insights.retrieval import evidence_section
from healthee.insights.validator import ValidationResult, validate, validate_json

__all__ = ["AnswerContext", "AnswerGate", "Block", "GateOutcome", "NOOP_EVENT", "Verdict"]

log = get_logger(__name__)


# ── Progress observer — a diagnostic seam, never a decision ──────────────────


def _noop_event(_event: dict) -> None:
    """The default observer. Costs one call and does nothing until a caller wants it."""
    return None


NOOP_EVENT: Callable[[dict], None] = _noop_event


def emit_event(on_event: Callable[[dict], None], event: dict) -> None:
    """Call a progress observer with one event, never letting it break the turn.

    This is the one place a broad ``except Exception`` is correct: the observer exists
    only to report progress to a client watching a stream (the coach's SSE twin), and a
    bug in it — or a write that raises because that client already disconnected — must
    never abort or corrupt a coach turn that is already billed and already running.
    """
    try:
        on_event(event)
    except Exception:
        log.exception("progress observer raised — ignored")


# ── Stage 1 · the question gate ──────────────────────────────────────────────

QuestionGate = Callable[[str], Domain | None]

_QUESTION_GATES: tuple[QuestionGate, ...] = (classify_refusal,)


def question_gates() -> tuple[QuestionGate, ...]:
    """The gates run over the QUESTION before any context build or model call."""
    return _QUESTION_GATES


def check_question(question: str) -> Domain | None:
    """The first refusal domain ``question`` hits, or None when it may be answered.

    A hit short-circuits the whole pipeline — the model is never called, so it cannot be
    prompted, jailbroken or cajoled past a hard guardrail (INTELLIGENCE §3 step 1).
    """
    for gate in question_gates():
        hit = gate(question)
        if hit is not None:
            return hit
    return None


# ── Stages 2–4 · context, retrieval, transport ───────────────────────────────


def user_context(question: str, user_id: UUID, tz: str, *, days: int) -> str:
    """The owner's v2-native context markdown — THE context stage for every surface.

    A one-line seam on purpose: it is what makes "context" a stage both surfaces provably
    share rather than two call sites that happen to agree today.
    """
    return build_context(user_id, tz, days=days, question=question)


def evidence(question: str, metrics: Sequence[str] | None = None) -> tuple[str, list[str]]:
    """The manifest-ranked EVIDENCE NOTES section + the ids embedded in full.

    Every surface but the coach: the daily action, briefing, recs and the
    sleep/activity/metric insights all still embed their top-N notes WHOLE.
    """
    return evidence_section(question, list(metrics or []))


def coach_evidence(question: str, metrics: Sequence[str] | None = None) -> tuple[str, list[str]]:
    """The COACH's own evidence stage — passages, not whole notes (``insights/evidence.py``).

    A second choke-point seam rather than a parameter on :func:`evidence`, for the same
    reason the tool loop is a ``Loop`` and not a flag: the coach's evidence shape is a
    real, documented difference from every other surface, and a seam says so where a
    boolean would hide it in a call site. Ranking is unchanged — both seams pick the
    same top-N notes; only what of each note ships differs.
    """
    return build_evidence(question, list(metrics or []))


def complete(
    client: LLMClient,
    messages: list[dict],
    *,
    tools: list[dict] | None = None,
    model: str | None = None,
    response_format: dict | None = None,
    reasoning: bool | None = None,
) -> ChatResponse:
    """The ONE call into the LLM transport — the seam a cost/budget stage plugs into.

    ``reasoning`` travels only when a caller actually set it: every surface but the
    coach leaves it ``None``, and a ``None`` that is not sent keeps their requests — and
    every test double of this protocol — byte-identical to before the parameter existed.
    """
    extra: dict[str, bool] = {} if reasoning is None else {"reasoning": reasoning}
    return client.complete(
        messages, tools=tools, model=model, response_format=response_format, **extra
    )


# ── Stages 5–7 · the answer gates ────────────────────────────────────────────


def _output_guard_gate(text: str, ctx: AnswerContext) -> GateOutcome:  # noqa: ARG001
    """Hard output guardrails — blocking, whatever the text cited or would validate."""
    rule = check_output(text)
    if rule is None:
        return GateOutcome()
    return GateOutcome(block=Block(rule.name, rule.response))


def _validator_gate(text: str, ctx: AnswerContext) -> GateOutcome:
    """The blocking citation validator — prose or JSON, same honesty rules."""
    result = validate_json(text) if ctx.json_mode else validate(text)
    return GateOutcome(issues=tuple(result.issues), validation=result)


def _action_claim_gate(text: str, ctx: AnswerContext) -> GateOutcome:
    """Never claim an action no tool performed this turn (``action_claims``)."""
    return GateOutcome(issues=tuple(claim_issues(text, ctx.acted_ok)))


def _structure_gate(text: str, ctx: AnswerContext) -> GateOutcome:  # noqa: ARG001
    """The surface's own answer CONTRACT — a shape that was not honoured is an issue.

    It reads the context, not the text, because the contract is about the payload the
    MODEL produced while ``text`` is what the surface RENDERED from it
    (``coach_answer.render``). Both are checked: the rendered prose faces every gate above
    unchanged, and this one says whether what it came from was what was asked for.
    """
    return GateOutcome(issues=ctx.structure_issues)


def _personal_claim_gate(text: str, ctx: AnswerContext) -> GateOutcome:
    """Never assert a value for owner-data that does not exist (``personal_claims``, #129).

    The gap every other gate leaves open: they check claims against the research corpus,
    and a sentence about the owner's own numbers cites nothing, so nothing checked it. It
    reads BOTH the text and the context because the two halves are different — a declared
    assertion is structural, the sentence scan is the backstop under it.
    """
    return GateOutcome(issues=personal_claim_issues(text, ctx.asserted, ctx.without_data))


_ANSWER_GATES: tuple[AnswerGate, ...] = (
    _output_guard_gate,  # the floor FIRST — a forbidden answer is never nudged
    _validator_gate,
    _action_claim_gate,
    _structure_gate,
    _personal_claim_gate,  # appended, never inserted: no gate's order is another's to move
)


def answer_gates() -> tuple[AnswerGate, ...]:
    """The gates run over every text candidate, in order. THE seam a new stage enters by."""
    return _ANSWER_GATES


def judge(text: str, ctx: AnswerContext) -> Verdict:
    """Run every answer gate over ``text``; a block short-circuits the rest."""
    issues: list[str] = []
    validation: ValidationResult | None = None
    for gate in answer_gates():
        outcome = gate(text, ctx)
        if outcome.block is not None:
            return Verdict(block=outcome.block, validation=outcome.validation or validation)
        issues.extend(outcome.issues)
        if outcome.validation is not None:
            validation = outcome.validation
    return Verdict(issues=tuple(issues), validation=validation)


# ── Stage 8 · the loop policy: gather, then answer, nudge once, then fall back ─


@dataclass(frozen=True)
class Turn:
    """One model turn: an answer candidate, or ``None`` when the turn produced none.

    ``text=None`` is how a surface says "I handled that turn myself — ask again". The
    coach returns it after running tool calls; that is the ONLY shape the tool loop
    takes in this module, which is why the loop is a parameter and not a fork.

    ``progressed=False`` on such a turn says "that round added nothing new" — the surface
    knows what a repeat looks like (the coach: same tool, same arguments), the driver
    knows what to do about it (stop gathering and force the answer). A loop that is not
    making progress should end on its own rather than run out of budget.
    """

    text: str | None
    progressed: bool = True


@dataclass(frozen=True)
class Outcome:
    """What the shared driver concluded — each surface shapes its own result from this."""

    text: str
    validation: ValidationResult | None = None
    refused: bool = False
    validated: bool = True


@dataclass(frozen=True)
class Loop:
    """A surface's three differences: produce a turn, carry a nudge back, describe itself.

    ``context`` is a callable rather than a value because the coach's ``acted_ok`` grows
    as tools run — it must be read at judgement time, not at loop entry.

    ``next_turn`` is asked with ``tools_allowed``: True while the gathering allowance
    lasts, False once it is spent (or the loop stalled). A tool-less surface ignores it;
    the coach stops offering ``tools=`` and tells the model to answer with what it has.

    ``max_gathering_turns`` is the allowance for rounds that run tools instead of
    answering. It defaults to 0 — a surface with no tools can never spend one — and it
    is NOT the answer budget: :func:`validation_retries` is reserved on top of it by
    :func:`drive`, so a question that needed twenty rounds of data arrives at its answer
    with exactly the same grounding tolerance as a trivial one.

    ``on_event`` is the coach's progress hook (its SSE twin, ``api/coach_stream.py``) —
    a surface with nothing watching leaves it at :data:`NOOP_EVENT`, and every call
    into it goes through :func:`emit_event` so a broken observer can never reach the
    turn itself.
    """

    next_turn: Callable[[bool], Turn]
    nudge: Callable[[str, Sequence[str]], None]
    label: str
    max_gathering_turns: int = 0
    context: Callable[[], AnswerContext] = field(default=AnswerContext)
    on_event: Callable[[dict], None] = NOOP_EVENT


def drive(loop: Loop) -> Outcome:
    """Run turns until one clears every gate, is blocked, or the honest fallback ships.

    Gathering and validation are two budgets, not one counter. They used to share
    ``max_turns``, which produced two defects at once: a question needing the full
    allowance of tool rounds exited having NEVER been asked for an answer, and a
    data-heavy question reached its one answer attempt with zero retries left while a
    trivial one kept them all. The questions needing the most data got the least
    grounding tolerance — exactly backwards.

    The fallback is still here and nowhere else: unvalidated text never ships
    (INTELLIGENCE §3, hole #2), and a blocked answer is returned without a retry.
    """
    state = _Progress()
    for turn_no in range(1, turn_budget(loop) + 1):
        tools_allowed = state.may_gather(loop)
        if not tools_allowed and state.gathered and state.out_of_time():
            log.warning(
                "%s: gathering hit its %.0fs deadline after %d round(s) — answering now",
                loop.label,
                gathering_deadline_s(),
                state.gathered,
            )
        turn = loop.next_turn(tools_allowed)
        if turn.text is None:
            if not tools_allowed:
                log.warning("%s: a tool-less turn produced no answer — honest fallback", loop.label)
                return Outcome(text=prompts.FALLBACK, validated=False)
            state.note_round(loop, turn)
            continue
        outcome = _settle(loop, turn.text, state, turn_no)
        if outcome is not None:
            return outcome
    log.warning("%s: exhausted its turn budget without a clean answer — fallback", loop.label)
    return Outcome(text=prompts.FALLBACK, validated=False)


def _settle(loop: Loop, text: str, state: _Progress, round_no: int) -> Outcome | None:
    """Judge one answer candidate; None means "nudged — ask the model again".

    ``round_no`` is the model round that produced ``text`` (``drive``'s own 1-based turn
    counter, which advances in lockstep with a tool loop's own round count — one call to
    ``next_turn`` per iteration on both sides). It is carried only to label the
    ``checking``/``revising`` progress events; the driver's policy does not read it.
    """
    emit_event(loop.on_event, {"stage": "checking", "round": round_no, "detail": None})
    verdict = judge(text, loop.context())
    if verdict.block is not None:
        return Outcome(text=verdict.block.response, refused=True, validated=False)
    if verdict.ok:
        return Outcome(text=text, validation=verdict.validation)
    if state.retries >= validation_retries():
        log.warning(
            "%s: candidate failed the gates on every attempt (%s) — honest fallback",
            loop.label,
            verdict.issues,
        )
        return Outcome(text=prompts.FALLBACK, validated=False)
    emit_event(loop.on_event, {"stage": "revising", "round": round_no, "detail": None})
    loop.nudge(text, verdict.issues)
    state.retries += 1
    return None


def nudge_turns(text: str, issues: Sequence[str], *, template: str | None = None) -> list[dict]:
    """The two conversation turns that carry a failed candidate back to the model.

    ``template`` lets a surface state the fix in ITS OWN output contract's terms: telling
    the coach to "end every sentence with a `[note_id]`" would be instructions for a
    format it no longer writes. The POLICY (one nudge per failed attempt, then the honest
    fallback) stays here and is shared; only the wording is the surface's.
    """
    listed = "\n".join(f"- {issue}" for issue in issues)
    return [
        {"role": "assistant", "content": text},
        {"role": "user", "content": (template or prompts.RETRY_NUDGE).format(issues=listed)},
    ]
