"""Shared no-network fakes for the OpenRouter transport — used by `test_client.py`,
`test_client_streaming.py` and `test_coach_reasoning.py`.

The transport now always calls `stream=True`, so every fake here is a chunk
ITERATOR, never a single object: `_FakeCompletions.create()` returns a `_FakeStream`
built from a scripted `chunks` list, or — when none is given — a two-chunk stream
that reproduces the pre-streaming fakes' plain "ok" response (one content delta, one
usage chunk), so every caller of `_client_with_fake()` written before streaming
existed keeps working unchanged.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from healthee.insights.client import OpenRouterClient


def _chunk(
    content: str | None = None,
    tool_calls: list[Any] | None = None,
    finish_reason: str | None = None,
) -> Any:
    """One streamed completion chunk carrying a content and/or tool-call delta."""
    delta = SimpleNamespace(content=content, tool_calls=tool_calls)
    choice = SimpleNamespace(delta=delta, finish_reason=finish_reason)
    return SimpleNamespace(choices=[choice])


def _usage_chunk(usage: Any) -> Any:
    """The final chunk ``stream_options={"include_usage": True}`` adds — no choices,
    same as OpenRouter's own shape."""
    return SimpleNamespace(choices=[], usage=usage)


def _tool_call_delta(
    index: int,
    *,
    call_id: str | None = None,
    name: str | None = None,
    arguments: str | None = None,
) -> Any:
    """One fragment of one streamed tool call, keyed by ``index``."""
    function = SimpleNamespace(name=name, arguments=arguments)
    return SimpleNamespace(index=index, id=call_id, function=function)


class _FakeStream:
    """A minimal stand-in for the SDK's streaming response: iterable once, closeable."""

    def __init__(self, chunks: list[Any]) -> None:
        self._chunks = chunks
        self.closed = False

    def __iter__(self) -> Any:
        return iter(self._chunks)

    def close(self) -> None:
        self.closed = True


class _FakeCompletions:
    def __init__(
        self,
        finish_reason: str | None = None,
        usage: Any = None,
        chunks: list[Any] | None = None,
    ) -> None:
        self.kwargs: dict[str, Any] | None = None
        self._finish_reason = finish_reason
        self._usage = usage
        self._chunks = chunks
        self.stream: _FakeStream | None = None

    def create(self, **kwargs: Any) -> Any:
        self.kwargs = kwargs
        chunks = self._chunks
        if chunks is None:
            # The old single-shot fakes' behaviour, reproduced as a two-chunk stream:
            # one content delta, then the final usage chunk.
            chunks = [
                _chunk(content="ok", finish_reason=self._finish_reason),
                _usage_chunk(self._usage),
            ]
        self.stream = _FakeStream(chunks)
        return self.stream


class _FakeSDK:
    def __init__(
        self,
        finish_reason: str | None = None,
        usage: Any = None,
        chunks: list[Any] | None = None,
    ) -> None:
        self.chat = SimpleNamespace(completions=_FakeCompletions(finish_reason, usage, chunks))


def _client_with_fake(
    finish_reason: str | None = None,
    usage: Any = None,
    chunks: list[Any] | None = None,
) -> tuple[OpenRouterClient, _FakeSDK]:
    client = OpenRouterClient()
    fake = _FakeSDK(finish_reason, usage, chunks)
    client._client = lambda: fake  # type: ignore[method-assign]  # inject the fake SDK
    return client, fake
