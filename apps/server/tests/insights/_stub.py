"""A deterministic, offline stub LLM client for the insights tests.

Implements the ``LLMClient`` protocol (``complete``) and counts calls, so tests
prove things like "the second endpoint call is served from cache — no second LLM
call" without any network.
"""

from __future__ import annotations

import json

from tests.insights._coach_stub import VALID_ANSWER_JSON, VALID_REPLY
from tests.insights._ids import ESTABLISHED_ID

from healthee.insights.client import ChatResponse
from healthee.insights.coach_answer import ROOT_KEY as _COACH_ROOT

# Re-exported so a test that drives BOTH surfaces through this stub can assert on the
# coach's reply without importing two helper modules for one conversation.
__all__ = ["MORNING_JSON", "VALID_ANSWER_JSON", "VALID_REPLY", "VALID_TEXT", "StubLLM"]

# A response that passes the blocking validator: one descriptive sentence + one
# interpretive sentence citing a real Established note (plain wording is fine).
VALID_TEXT = (
    f"Your recent numbers look steady. Consistent activity may support fitness [{ESTABLISHED_ID}]."
)

# The merged morning answer (#95) in the shape `json_shapes` registers: two validating
# fields, one call. A test that wants the fast path hands this to `StubLLM(json_text=…)`.
MORNING_JSON = json.dumps({"briefing": VALID_TEXT, "action": VALID_TEXT})


class StubLLM:
    """Scripted LLM: returns each queued response in turn (repeats the last).

    ``messages`` records what each call was actually asked, so a test can prove a
    surface put something in the prompt (a caller-supplied intent, a calibration band)
    rather than only that the answer came back.

    ``json_text`` is what a JSON-mode call gets, when a test supplies one. It is a
    SEPARATE script because prose and JSON surfaces interleave inside one chain run
    (recs, the merged morning call, the sleep line) and a single ordered list would make
    every test depend on the chain's internal call order. Left ``None``, a JSON call gets
    the prose script — which is the pre-#95 behaviour and, deliberately, an invalid JSON
    answer: a test that wants the degraded path needs no special stub for it.

    ``coach_text`` is the third script, for the same reason and one more: since #128 the
    coach answers in its own contract, so prose handed to it is not an answer at all. It
    is selected off the SYSTEM turn declaring that contract rather than off ``tools`` or
    ``response_format`` — the coach withdraws its tools on the last round and cannot ask
    for JSON mode while offering them, so neither of those identifies the surface for the
    whole conversation and a stub that guessed wrong would report a fallback as a refusal.
    """

    def __init__(
        self,
        responses: list[str] | None = None,
        *,
        json_text: str | None = None,
        coach_text: str = VALID_ANSWER_JSON,
    ) -> None:
        self._responses = list(responses or [VALID_TEXT])
        self._json_text = json_text
        self._coach_text = coach_text
        self.calls = 0
        self.messages: list[list[dict]] = []

    def complete(  # noqa: ARG002
        self,
        messages: list[dict],
        *,
        tools=None,
        model: str | None = None,
        response_format=None,
        reasoning: bool | None = None,
        on_text=None,
    ) -> ChatResponse:
        idx = min(self.calls, len(self._responses) - 1)
        self.calls += 1
        self.messages.append(list(messages))
        if self._is_coach(messages):
            return ChatResponse(text=self._coach_text)
        json_mode = bool(response_format) and response_format.get("type") == "json_object"
        if json_mode and self._json_text is not None:
            return ChatResponse(text=self._json_text)
        return ChatResponse(text=self._responses[idx])

    @staticmethod
    def _is_coach(messages: list[dict]) -> bool:
        """True when the system turn carries the coach's answer contract (``coach_answer``)."""
        return any(_COACH_ROOT in str(m.get("content") or "") for m in messages)
