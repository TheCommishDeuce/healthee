"""The coach's TURN SHAPE — the one thing ``grounded_ask`` cannot express.

``coach.py`` contributes two things to the shared choke point: a message layout, and a
bounded tool loop. This is the loop. It is a ``pipeline.Loop.next_turn`` implementation
and nothing else — no gate, no policy, no decision about what ships. Every honesty stage
still lives in ``pipeline.py`` and judges what :meth:`ToolLoop.next_turn` returns.

It moved out of ``coach.py`` when that file reached the standards' 400-line ceiling, and
the seam is the one the module docstring there already drew: the LAYOUT of a coach turn
is one reason to change, and the SHAPE of a coach turn is another.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

from healthee.core.config import get_settings
from healthee.core.logging import get_logger
from healthee.insights import (
    coach_answer,
    coach_draft,
    coach_tools,
    personal_claims,
    pipeline,
    prompts,
)
from healthee.insights.client import LLMClient, coach_model

log = get_logger(__name__)

# The wire contract's own cap (INTELLIGENCE section 3, the owner's 2026-09-19 call): at
# most one `draft` progress event every 100ms per round, so a fast model does not flood
# the SSE connection with one frame per token. A module constant, not a setting — it is
# what the wire promises the app, not a deployment knob.
_DRAFT_THROTTLE_S = 0.1

# Said once, when the gathering allowance runs out (or the loop stalls) and the tools are
# withdrawn. Without it the model would face a silent, unexplained loss of its tools; with
# it the last round is a real answer attempt instead of a wasted one. It asks for honesty
# about the gap rather than a guess — the validator would refuse the guess anyway, but a
# refused answer the owner never sees is a worse outcome than a plainly stated limit.
_ANSWER_NOW = (
    "You have no more tool calls available. Answer the question now using only the data "
    "already in this conversation. If something you wanted is missing, say plainly what "
    "you could not check — do not estimate or invent a number."
)

# JSON mode, but ONLY on a round that offers no tools. The two are not reliably
# combinable across the providers behind OpenRouter (a JSON-constrained response and a
# function call are two different things for a model to emit), and a round that answers
# is exactly a round that ran out of tools to offer or chose not to use them. Asking for
# both on every round would risk the tool loop itself to tidy a format the instruction
# already gets right; `coach_answer._json_object` covers the rest.
_JSON_OBJECT = {"type": "json_object"}


def reasoning_for_round(tools_allowed: bool) -> bool | None:
    """What ``Settings.coach_reasoning`` means for THIS round of the loop.

    ``None`` = say nothing, the model's own default (thinking on for a reasoning tier);
    ``False`` = ask for no thinking. "on" never sends anything — the shipped request.
    "off" asks every round. "answer_only" asks only while tools are in play: the rounds
    that decide which metric to query, where thinking buys nothing, and leaves the round
    that writes the answer at the model default.
    """
    mode = get_settings().coach_reasoning
    if mode == "off":
        return False
    if mode == "answer_only":
        return False if tools_allowed else None
    return None


class _DraftThrottle:
    """Coalesces one round's content-delta callbacks into throttled ``draft`` events.

    ``on_text`` is fed the FULL cumulative text on every provider content delta
    (``client_stream.accumulate``'s own contract) and only emits when
    :data:`_DRAFT_THROTTLE_S` has passed since this round's last emission.
    :meth:`flush` unconditionally emits the round's final prose if it differs from
    what was last sent — the wire contract's "always emit the final state" clause —
    so the throttle window can never swallow the round's last word.
    """

    def __init__(self, emit: Callable[[str], None], clock: Callable[[], float]) -> None:
        self._emit = emit
        self._clock = clock
        self._last_emitted_at: float | None = None
        self._last_prose = ""

    def on_text(self, cumulative: str) -> None:
        prose = coach_draft.draft_prose(cumulative)
        if not prose or prose == self._last_prose:
            return
        now = self._clock()
        if self._last_emitted_at is not None and now - self._last_emitted_at < _DRAFT_THROTTLE_S:
            return
        self._send(prose, now)

    def flush(self, final_text: str) -> None:
        prose = coach_draft.draft_prose(final_text)
        if prose and prose != self._last_prose:
            self._send(prose, self._clock())

    def _send(self, prose: str, now: float) -> None:
        self._last_emitted_at = now
        self._last_prose = prose
        self._emit(prose)


@dataclass
class ToolLoop:
    """The coach's turn shape — the ONE thing ``grounded_ask`` cannot express.

    It holds the state a bounded tool loop needs across turns: the conversation, which
    action tools returned ok (the anti-hallucination gate reads it at judgement time),
    every invocation made (so a repeat is recognisable), and whether the tools have
    already been withdrawn (so the "answer now" instruction is said exactly once).
    """

    client: LLMClient
    convo: list[dict]
    user_id: UUID
    tz: str
    invocations: list[dict] = field(default_factory=list)
    acted_ok: set[str] = field(default_factory=set)
    seen_calls: set[tuple[str, str]] = field(default_factory=set)
    tools_withdrawn: bool = False
    raw_answer: str = ""
    structure_issues: tuple[str, ...] = ()
    asserted: tuple[str, ...] = ()
    without_data: frozenset[str] = frozenset()
    # The coach's own 1-based round counter — advances once per `next_turn` call, in
    # lockstep with `pipeline.drive`'s own turn counter, which is what lets `pipeline`
    # label a `checking`/`revising` event with the same round a `thinking`/`tool` event
    # here used, with neither side importing the other's counter.
    round: int = 0
    # The coach's progress hook (its SSE twin, `api/coach_stream.py`); a no-op until a
    # caller wants one. Every call goes through `pipeline.emit_event`, never directly.
    on_event: Callable[[dict], None] = pipeline.NOOP_EVENT
    # Injectable so a test can prove the 100ms throttle without a real sleep. Resolved
    # to `time.monotonic` as a plain field default (a function reference, not a mutable
    # container dataclass would otherwise reject) rather than inside `next_turn` — every
    # round of one turn shares the SAME clock, which is the point of it being state.
    clock: Callable[[], float] = time.monotonic

    def next_turn(self, tools_allowed: bool) -> pipeline.Turn:
        """One model turn: run any tools it asked for, or RENDER the answer it returned.

        The turn the driver judges is the rendered prose, never the payload: every answer
        gate reads the words the owner would actually see. What the payload was is carried
        separately, on :meth:`answer_context`, so a broken contract is an issue rather
        than a silent degradation back to free text.

        Every round streams its own live DRAFT (the owner's 2026-09-19 call,
        INTELLIGENCE section 3): a fresh :class:`_DraftThrottle` per round, so a rewrite's
        draft always starts from empty text rather than continuing the rejected one. A
        round that never produces content (a tool-call round) never calls ``on_text`` at
        all, so it emits no ``draft`` event — nothing to flush either.
        """
        self.round += 1
        round_no = self.round
        pipeline.emit_event(self.on_event, {"stage": "thinking", "round": round_no, "detail": None})
        if not tools_allowed:
            self._withdraw_tools()
        tools = coach_tools.COACH_TOOLS if tools_allowed else None
        throttle = _DraftThrottle(self._draft_emitter(round_no), self.clock)
        response = pipeline.complete(
            self.client,
            self.convo,
            tools=tools,
            model=coach_model(),
            response_format=None if tools_allowed else _JSON_OBJECT,
            reasoning=reasoning_for_round(tools_allowed),
            on_text=throttle.on_text,
        )
        if response.tool_calls:
            progressed = self._run_tools(response)
            return pipeline.Turn(text=None, progressed=progressed)
        throttle.flush(response.text or "")
        return pipeline.Turn(text=self._rendered(response.text))

    def _draft_emitter(self, round_no: int) -> Callable[[str], None]:
        """One round's ``draft`` progress event, bound to the round that produced it."""

        def emit(prose: str) -> None:
            pipeline.emit_event(self.on_event, {"event": "draft", "round": round_no, "text": prose})

        return emit

    def _rendered(self, raw: str) -> str:
        """The answer as prose, with its structural issues recorded for the gate.

        An unparseable payload hands the RAW text on rather than nothing, so the hard
        output guardrails still see whatever the model wrote — but the structure gate has
        an issue by then, so it can never ship. "Fall back to prose" is deliberately not a
        branch here: it would reinstate the uncited-claim path on exactly the turns where
        the model was already ignoring instructions.
        """
        self.raw_answer = raw or ""
        answer, self.structure_issues = coach_answer.parse(self.raw_answer)
        text = coach_answer.render(answer) if answer is not None else self.raw_answer
        self.asserted = answer.asserts if answer is not None else ()
        # Gathered here rather than in the gate because only the surface knows the owner
        # (#129). Reads nothing when the answer neither declares a subject nor records an
        # event, which is most answers; the RULE over the result stays in the registry.
        self.without_data = personal_claims.subjects_without_data(
            self.user_id, self.tz, self.asserted, text
        )
        return text

    def nudge(self, text: str, issues: Sequence[str]) -> None:  # noqa: ARG002
        """Carry the failed PAYLOAD back to the model, in its own contract's words.

        The payload, not ``text``: the model is being asked to correct a JSON object, and
        showing it prose it never wrote is an invitation to answer in prose next time.
        """
        self.convo.extend(
            pipeline.nudge_turns(self.raw_answer, issues, template=prompts.STRUCTURED_RETRY_NUDGE)
        )

    def answer_context(self) -> pipeline.AnswerContext:
        """Read at judgement time, not loop entry — ``acted_ok`` grows as tools run."""
        return pipeline.AnswerContext(
            acted_ok=frozenset(self.acted_ok),
            structure_issues=self.structure_issues,
            asserted=self.asserted,
            without_data=self.without_data,
        )

    def _withdraw_tools(self) -> None:
        """Tell the model, once, that it must answer with what it already has."""
        if self.tools_withdrawn:
            return
        self.tools_withdrawn = True
        self.convo.append({"role": "user", "content": _ANSWER_NOW})

    def _run_tools(self, response: Any) -> bool:
        """Execute each requested tool; return whether the round learned anything new.

        A round is "no progress" only when EVERY call in it repeats an invocation already
        made — same tool, same arguments, hence the same answer. One repeat alongside a
        genuinely new call is still a round that gathered something.
        """
        self.convo.append(_assistant_tool_message(response))
        fresh = False
        for call in response.tool_calls:
            name = call.function.name
            args = _parse_args(call.function.arguments)
            fresh |= self._record_call(name, args)
            result = coach_tools.execute_tool(name, args, self.user_id, self.tz)
            pipeline.emit_event(
                self.on_event, {"stage": "tool", "round": self.round, "detail": name}
            )
            if name in coach_tools.ACTION_TOOLS and result.get("ok"):
                self.acted_ok.add(name)
            self.invocations.append({"tool": name, "args": args, "result": result})
            self.convo.append(
                {"role": "tool", "tool_call_id": call.id, "content": coach_tools.dumps(result)}
            )
        return fresh

    def _record_call(self, name: str, args: dict) -> bool:
        """Remember this exact invocation; False when it has been made before."""
        signature = (name, json.dumps(args, sort_keys=True, default=str))
        if signature in self.seen_calls:
            log.info("coach repeated tool call: %s — no new information this round", name)
            return False
        self.seen_calls.add(signature)
        return True


def _assistant_tool_message(response: Any) -> dict:
    """Rebuild the assistant turn that requested tools (OpenAI tool-call shape)."""
    return {
        "role": "assistant",
        "content": response.text or "",
        "tool_calls": [
            {
                "id": call.id,
                "type": "function",
                "function": {"name": call.function.name, "arguments": call.function.arguments},
            }
            for call in response.tool_calls
        ],
    }


def _parse_args(raw: str | None) -> dict:
    """Parse a tool call's JSON arguments; a malformed blob degrades to empty args."""
    try:
        parsed = json.loads(raw or "{}")
    except (json.JSONDecodeError, TypeError) as exc:
        log.warning("coach tool arguments unparseable (%s) — using empty args", exc)
        return {}
    return parsed if isinstance(parsed, dict) else {}
