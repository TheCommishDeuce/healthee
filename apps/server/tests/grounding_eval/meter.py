"""A metered LLM client — what one question actually cost, provider-counted.

Wraps the real transport and implements the same ``LLMClient`` protocol, so the harness
injects it exactly where a test injects a stub (``grounded_ask(client=…)`` /
``run_coach(client=…)``) and the pipeline is unchanged. It only observes.

The numbers come from ``ChatResponse.usage`` — the PROVIDER's counts, not a
characters/4 estimate. That distinction is the whole reason this exists: a token
estimate cannot settle "did trimming the evidence block cost us grounding", because the
two arms would differ by an estimator's error as much as by the change. When a provider
reports no usage at all the call is counted in ``unmetered_calls`` rather than silently
treated as free — "we don't know" is not "zero" (standards §Errors).
"""

from __future__ import annotations

from dataclasses import dataclass, replace

from healthee.insights.client import ChatResponse, LLMClient


@dataclass(frozen=True)
class Meter:
    """Everything one question spent: calls, tool rounds, and provider-counted tokens.

    ``tool_rounds`` counts the completions that came back asking for tools instead of
    answering — the coach's gathering rounds. ``llm_calls`` counts every completion, so
    ``llm_calls - tool_rounds`` is how many answer attempts the gates saw.

    ``cached_prompt_tokens`` is the provider-counted prefix-cache hit share of
    ``prompt_tokens`` (``Usage.cached_prompt_tokens``) — same treatment as the other
    three: summed across every completion, reset with them, and left at 0 (not "unknown")
    when a response carries no usage at all, because a call the provider didn't meter is
    not evidence the cache missed.
    """

    llm_calls: int = 0
    tool_rounds: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0
    reasoning_tokens: int = 0
    cached_prompt_tokens: int = 0
    unmetered_calls: int = 0

    def plus(self, response: ChatResponse) -> Meter:
        """This meter with one more completion folded in (frozen — never mutated)."""
        usage = response.usage
        return replace(
            self,
            llm_calls=self.llm_calls + 1,
            tool_rounds=self.tool_rounds + (1 if response.tool_calls else 0),
            prompt_tokens=self.prompt_tokens + (usage.prompt_tokens if usage else 0),
            completion_tokens=self.completion_tokens + (usage.completion_tokens if usage else 0),
            reasoning_tokens=self.reasoning_tokens + (usage.reasoning_tokens if usage else 0),
            cached_prompt_tokens=self.cached_prompt_tokens
            + (usage.cached_prompt_tokens if usage else 0),
            unmetered_calls=self.unmetered_calls + (0 if usage else 1),
        )


class MeteredClient:
    """Delegates every completion to ``inner`` and remembers what it cost.

    ``reset()`` between questions; ``meter`` is the running total since the last reset.
    Deliberately not thread-safe: the harness runs one question at a time on purpose, so
    a slow question cannot be mistaken for a cheap one that happened to overlap it.
    """

    def __init__(self, inner: LLMClient) -> None:
        self._inner = inner
        self.meter = Meter()

    def reset(self) -> None:
        self.meter = Meter()

    def complete(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        model: str | None = None,
        response_format: dict | None = None,
    ) -> ChatResponse:
        response = self._inner.complete(
            messages, tools=tools, model=model, response_format=response_format
        )
        self.meter = self.meter.plus(response)
        return response
