"""A scriptable offline LLM stub for the coach control-flow tests.

Unlike ``_stub.StubLLM`` (text-only), this one can emit OpenAI-shaped tool calls,
so a test can script "call query_metric, then answer" without any network. It also
records the ``tools`` passed on each call (to assert tools were/weren't offered), the
``messages`` each call was asked with (to assert what the loop put in the prompt), and
counts calls (to prove a refusal never reaches the model).

Since #128 the coach answers in a CONTRACT (``insights/coach_answer``) rather than in
prose, so :func:`answer_turn` is what a scripted answer looks like now and
:func:`text_turn` is what a model IGNORING the contract looks like. Both are needed and
they mean different things: several tests below exist precisely to prove that raw prose
— however well cited — no longer ships.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from dataclasses import dataclass, field

from tests.insights._ids import ESTABLISHED_ID

from healthee.insights.client import ChatResponse


@dataclass
class StubFunction:
    name: str
    arguments: str


@dataclass
class StubToolCall:
    id: str
    function: StubFunction
    type: str = "function"


def tool_call(call_id: str, name: str, arguments: str) -> StubToolCall:
    return StubToolCall(id=call_id, function=StubFunction(name=name, arguments=arguments))


def text_turn(text: str) -> ChatResponse:
    """A turn of RAW PROSE — i.e. a model that did not honour the answer contract."""
    return ChatResponse(text=text)


def answer_payload(
    opening: str = "", claims: Sequence[tuple] = (), asserts: Sequence[str] = ()
) -> dict:
    """The ``coach_answer`` payload for an opening plus ``(text, note_ids, grade)`` claims.

    ``asserts`` is the owner-subjects the answer declares a value for (#129). It defaults
    to empty because most scripted answers assert nothing about the owner's data, which is
    also what the field means.
    """
    return {
        "coach_answer": {
            "opening": opening,
            "claims": [
                {"text": text, "note_ids": list(ids), "grade": grade} for text, ids, grade in claims
            ],
            "asserts": list(asserts),
        }
    }


def answer_turn(
    opening: str = "", claims: Sequence[tuple] = (), asserts: Sequence[str] = ()
) -> ChatResponse:
    """A turn in the shipped answer contract — what a compliant model returns."""
    return ChatResponse(text=json.dumps(answer_payload(opening, claims, asserts)))


# The canonical good answer, and the prose it renders to. Kept as a pair so every test
# that asserts on the reply is asserting on what the RENDERER produces rather than on a
# string somebody typed twice; `test_coach_answer` pins the pair itself.
COACH_OPENING = "Your recent numbers look steady."
COACH_CLAIM = "Consistent activity may support fitness"
VALID_ANSWER = answer_payload(COACH_OPENING, [(COACH_CLAIM, [ESTABLISHED_ID], "Established")])
VALID_ANSWER_JSON = json.dumps(VALID_ANSWER)
VALID_REPLY = f"{COACH_OPENING}\n\n- {COACH_CLAIM} [{ESTABLISHED_ID}]."


def valid_turn() -> ChatResponse:
    """The scripted answer every control-flow test uses when it needs a shippable one."""
    return ChatResponse(text=VALID_ANSWER_JSON)


def opening_turn(text: str, asserts: Sequence[str] = ()) -> ChatResponse:
    """An answer that is only its descriptive opening — what a plain report looks like.

    It renders to ``text`` unchanged, which is why the control-flow tests that are about
    something ELSE (a fake action confirmation, a hard guardrail) use this: they get to
    keep asserting on the exact sentence they are about.
    """
    return answer_turn(opening=text, asserts=asserts)


def claim_turn(text: str, note_ids: Sequence[str] = (), grade: str = "") -> ChatResponse:
    """An answer that is one claim — the channel every interpretive sentence must use."""
    return answer_turn(claims=[(text, list(note_ids), grade)])


def tool_turn(*calls: StubToolCall) -> ChatResponse:
    return ChatResponse(text="", tool_calls=list(calls))


@dataclass
class CoachStub:
    """Returns each scripted ChatResponse in turn (repeats the last one)."""

    script: list[ChatResponse]
    calls: int = 0
    tools_seen: list = field(default_factory=list)
    messages_seen: list[list[dict]] = field(default_factory=list)

    def complete(  # noqa: ARG002
        self,
        messages: list[dict],
        *,
        tools=None,
        model: str | None = None,
        response_format=None,
        reasoning: bool | None = None,
    ) -> ChatResponse:
        self.tools_seen.append(tools)
        self.messages_seen.append(list(messages))
        response = self.script[min(self.calls, len(self.script) - 1)]
        self.calls += 1
        return response


class NoCallStub:
    """Fails if the model is ever called — proves a refusal short-circuits pre-LLM."""

    calls = 0

    def complete(  # noqa: ARG002
        self,
        messages: list[dict],
        *,
        tools=None,
        model: str | None = None,
        response_format=None,
        reasoning: bool | None = None,
    ) -> ChatResponse:
        raise AssertionError("the LLM must not be called for a refused question")
