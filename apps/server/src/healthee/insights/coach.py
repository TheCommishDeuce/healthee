"""The AI coach — the tool-calling surface, ROUTED THROUGH the shared choke point.

The coach is the flagship honesty surface (INTELLIGENCE §4). It used to be
*enforced-equivalent* to the choke point rather than *routed through* it: it called the
same primitives (``classify_refusal``, ``check_output``, ``validate``, the honest
fallback) from its own loop, in its own order, so every rule added to the choke point
had to be mirrored here by hand — and one already had been (the output guardrail, in two
places). That mirror rule is gone. Every honesty stage now lives once, in
``pipeline.py``, and this module contributes exactly two things ``grounded_ask`` cannot:

  * a message LAYOUT — coach persona + context in the system turn, conversation after it;
  * a bounded TOOL LOOP, expressed as ``pipeline.Loop.next_turn`` returning
    ``Turn(text=None)`` for a round that ran tools instead of answering — and
    ``Turn(progressed=False)`` when that round only repeated calls it had already made.
    The gathering allowance (:data:`GATHERING_ROUNDS`) is the coach's alone; the answer
    and its validation retries are the pipeline's, reserved on top;
  * an answer CONTRACT — the model returns claims as data and ``coach_answer`` renders
    the prose, so a claim cannot reach the owner without the ids it rests on (#128). The
    contract is the coach's, but nothing about the gates is: the rendered text is what
    every stage judges, and a broken contract enters the same registry as any other issue.
    The contract also carries what the answer asserts about the OWNER's data (#129), and
    this module reads how much of that data exists — the two facts only a surface can
    supply to ``pipeline._personal_claim_gate``.

Everything else — the refusal gate before any tool runs, the hard output guardrails, the
blocking validator on every final answer, the anti-hallucination gate, the nudged
retries and then ``prompts.FALLBACK`` — is the same code the insight surfaces run.
``tests/insights/test_pipeline_shared.py`` proves it by injecting a stage into the shared
registry and asserting BOTH surfaces obey it, and fails if any surface reaches a
primitive directly.

The system message is ``COACH_SYSTEM_PROMPT`` (docs/COACH_PROMPT.md verbatim); the
context is the history-rich ``build_coach_context``; the tools are ``COACH_TOOLS``.

Two neighbours hold the halves this file names, because it reached the standards'
400-line ceiling and those are its two other reasons to change:
``coach_loop.ToolLoop`` is the turn SHAPE, and ``coach_thread`` is what reaches the
prompt at all — the bounded history, the refusal screen over every turn of it, and the
subject the owner arrived with.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from uuid import UUID

from healthee.analytics import coverage
from healthee.core.logging import get_logger
from healthee.insights import coach_answer, coach_loop, coach_thread, pipeline
from healthee.insights.client import LLMClient, get_client
from healthee.insights.coach_context import DEFAULT_COACH_DAYS, build_coach_context, coach_evidence
from healthee.insights.coach_prompt import COACH_SYSTEM_PROMPT

log = get_logger(__name__)

# The GATHERING allowance — rounds the model may spend running tools instead of
# answering. It is a ceiling, not a spend: narrow questions were measured converging in
# TWO rounds against a live instance (docs/VERIFICATION_2026_08_01.md §7) and never touch
# the rest, and an unused round costs nothing. It used to be 5
# AND it doubled as the answer budget, so a question that legitimately needed five rounds
# of data exited having never been asked for an answer, and a four-round one reached its
# single answer attempt with zero validation retries left. `pipeline.validation_retries`
# is now reserved on top of this by `pipeline.drive`, so gathering can be generous without
# taking grounding tolerance away from exactly the questions that need it most.
GATHERING_ROUNDS = 20

_GREETING = "Ask me anything about your sleep, activity, recovery, or logged routines."


@dataclass
class CoachResult:
    """The coach's reply plus its grounding + which tools actually ran this turn.

    ``grade_floor`` is the WEAKEST evidence grade among the answer's valid citations —
    the floor the whole reply rests on, not an average and not the best note in it. The
    validator has always computed it (``validator._grade_floor``) and every other surface
    already carries it; the coach — the surface where an owner most needs to know how
    firm the ground is — dropped it on the floor (#84). ``None`` means the answer cited
    nothing gradeable, which is a different statement from a weak grade and stays
    distinguishable.

    ``data_coverage`` is §3's third piece of metadata (#89): how many days of each metric
    this turn READ the window actually held (:func:`_metrics_read`). ``None`` only for a
    greeting or a pre-LLM refusal — the two replies that rest on no data at all.

    ``answered`` is whether this turn produced an ANSWER to a question at all, and it is
    the router's fourth refund branch. It exists because the greeting was not covered by
    the other three: a request carrying no owner turn returns a fixed sentence with
    ``refused=False, validated=True``, so ``routers/coach.py`` charged one of the owner's
    twenty for a reply no model wrote and no question asked for. "A slot is never billed
    for an answer we did not deliver" is the router's own contract, and a canned greeting
    is not an answer we delivered. Not folded into ``refused``/``validated``: a greeting
    is neither a refusal nor a failed grounding, and blurring three different outcomes
    into one flag is how the meter stops being able to say what happened.
    """

    reply: str
    citations: list[str] = field(default_factory=list)
    personal_findings: list[str] = field(default_factory=list)
    grade_floor: str | None = None
    tool_calls: list[dict] = field(default_factory=list)
    refused: bool = False
    validated: bool = True
    answered: bool = True
    data_coverage: dict | None = None


def run_coach(
    messages: list[dict],
    user_id: UUID,
    tz: str,
    *,
    client: LLMClient | None = None,
    context_days: int = DEFAULT_COACH_DAYS,
    topic: str | None = None,
    on_event: Callable[[dict], None] | None = None,
) -> CoachResult:
    """Answer the conversation grounded in ``user_id``'s data + the graded corpus.

    Refusals short-circuit before any tool call; the final answer is always
    validated (or the honest fallback ships). ``client`` is injectable for tests.
    Every tool the loop runs acts on ``user_id`` only — the coach can neither read
    nor write another owner's data.

    ``topic`` is the subject the owner arrived with — which screen they pressed "ask the
    coach" on. Five surfaces link into the coach and two of them are about something
    specific, and until now the server never learned what: the app seeded the subject as
    the first user turn, so grounding was whatever the model inferred from that prose.
    With it, ``coach_thread.retrieval_key`` ranks the context and the evidence on the
    subject as well as the question.

    ⛔ **It is context, never evidence.** It is screened by the same refusal gate as the
    owner's own turns before any model call (``coach_thread.screen``), it reaches the
    model only inside ``coach_thread.topic_block``'s fence, and it buys no exemption from
    anything downstream — the answer that follows faces the identical validator, hard
    output guardrails, anti-hallucination and personal-claims gates. Nothing in a topic
    becomes true by being sent.

    ``on_event`` is the coach's SSE twin's progress hook (``api/coach_stream.py``) —
    called with ``{"stage": ..., "round": ..., "detail": ...}`` as the turn proceeds.
    ``None`` (every caller but the stream) behaves and outputs byte-identically to
    before this parameter existed: every call into it is wrapped in
    ``pipeline.emit_event``, which never lets it affect what ships.
    """
    emit = on_event or pipeline.NOOP_EVENT
    history = coach_thread.recent(messages)
    question = coach_thread.last_user(history)
    if not question:
        # Nothing was asked, so nothing is answered and nothing may be charged.
        return CoachResult(reply=_GREETING, answered=False)
    refusal = coach_thread.screen(history, topic)
    if refusal is not None:
        log.info("coach refused pre-LLM: domain=%s", refusal.name)
        return CoachResult(reply=refusal.template, refused=True)
    client = client or get_client()
    pipeline.emit_event(emit, {"stage": "context", "round": 0, "detail": None})
    convo = _initial_messages(history, question, user_id, tz, context_days, topic)
    result = _loop(client, convo, user_id, tz, emit)
    result.data_coverage = coverage.measured_payload(
        user_id, tz, _metrics_read(result.tool_calls), context_days
    )
    return result


def coach_reply_payload(result: CoachResult) -> dict:
    """The wire shape one coach turn renders to — the ONE function both endpoints share.

    Extracted from ``routers/coach.post_coach`` so its streaming twin
    (``api/coach_stream.py``) ships the exact same ``answer`` payload rather than a
    second, hand-kept copy of this dict — the CLAUDE.md rule against two definitions
    of one thing, applied to a response shape instead of a metric.
    """
    return {
        "reply": result.reply,
        "citations": result.citations,
        "personal_findings": result.personal_findings,
        # The weakest grade among the cited notes — INTELLIGENCE §3's promised response
        # metadata. `null` = nothing gradeable was cited, which is not the same as a
        # weak grade.
        "grade_floor": result.grade_floor,
        # INTELLIGENCE §3's third piece of response metadata (#89): how many days of
        # each metric this turn read the window actually held (`analytics.coverage`).
        "data_coverage": result.data_coverage,
        "tool_calls": result.tool_calls,
        "refused": result.refused,
        "validated": result.validated,
    }


def _metrics_read(invocations: list[dict]) -> list[str]:
    """The metrics this turn's tools actually read — the answer's own data scope.

    The coach declares no metric list the way ``grounded_ask`` does, and picking one for
    it would be inventing a scope. It does not need one: COACH_PROMPT's absolute rule is
    that NUMBERS COME ONLY FROM TOOL RESULTS, so the metrics the tools read are exactly
    the metrics the answer's numbers came from (INTELLIGENCE §4).

    Empty when the turn read none — a real state (the answer came from the standing
    context and the corpus), and ``coverage.payload`` keeps it distinguishable from
    "we have no data" by still naming the window.
    """
    return [
        metric
        for call in invocations
        if (metric := str(call.get("args", {}).get("metric", "")).strip())
    ]


def _loop(
    client: LLMClient, convo: list[dict], user_id: UUID, tz: str, on_event: Callable[[dict], None]
) -> CoachResult:
    """The bounded tool loop, driven by the shared pipeline (one gate set, one policy)."""
    tool_loop = coach_loop.ToolLoop(
        client=client, convo=convo, user_id=user_id, tz=tz, on_event=on_event
    )
    outcome = pipeline.drive(
        pipeline.Loop(
            next_turn=tool_loop.next_turn,
            nudge=tool_loop.nudge,
            label="coach",
            max_gathering_turns=GATHERING_ROUNDS,
            context=tool_loop.answer_context,
            on_event=on_event,
        )
    )
    return _result(outcome, tool_loop.invocations)


def _result(outcome: pipeline.Outcome, invocations: list[dict]) -> CoachResult:
    """The ONLY path that turns a pipeline outcome into the reply (accepted text only)."""
    if outcome.refused:
        return CoachResult(
            reply=outcome.text, tool_calls=invocations, refused=True, validated=False
        )
    if not outcome.validated or outcome.validation is None:
        return CoachResult(reply=outcome.text, tool_calls=invocations, validated=False)
    return CoachResult(
        reply=outcome.text,
        citations=outcome.validation.citations,
        personal_findings=outcome.validation.personal_findings,
        grade_floor=outcome.validation.grade_floor,
        tool_calls=invocations,
        validated=True,
    )


def _initial_messages(
    history: list[dict],
    question: str,
    user_id: UUID,
    tz: str,
    context_days: int,
    topic: str | None = None,
) -> list[dict]:
    """System (coach prompt + context + evidence + the output contract) then the conversation.

    ``COACH_SYSTEM_PROMPT`` is ``docs/COACH_PROMPT.md`` verbatim and is pinned
    byte-for-byte by a test; the answer contract is APPENDED here exactly as the context
    and evidence blocks are, so the voice document stays the voice document and the
    envelope lives with the parser that enforces it (``coach_answer.ANSWER_SHAPE``).

    ``topic`` enters twice and in two different roles, which is the whole distinction
    the feature rests on: as a RANKING input to the context and evidence builders
    (``coach_thread.retrieval_key`` — it changes which notes and findings the model is
    shown), and as a FENCED subject line at the end of the system turn (it says what the
    conversation is about and states that it is not a claim). It is never a sentence the
    model is asked to support.
    """
    ranked_on = coach_thread.retrieval_key(question, topic)
    context = build_coach_context(ranked_on, user_id, tz, days=context_days)
    evidence = coach_evidence(ranked_on)
    # Order is for the provider's prompt cache, which matches on a byte-identical PREFIX:
    # the parts that repeat across questions (the prompt, then the evidence notes, then
    # the answer contract) come first, and the parts that change per owner and per day
    # (their data, the turn's subject) come last. The old order put the owner's data
    # ahead of the ~40k-token evidence block, so a same-day question on the same notes
    # missed the cache at the second section; measured coach cache hit was 44%.
    system = (
        f"{COACH_SYSTEM_PROMPT}\n\n{evidence}\n\n{coach_answer.ANSWER_SHAPE}"
        f"\n\n# THE USER'S DATA (CONTEXT)\n\n{context}{coach_thread.topic_block(topic)}"
    )
    return [{"role": "system", "content": system}, *history]
