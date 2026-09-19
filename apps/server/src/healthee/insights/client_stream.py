"""Assembles one completion out of a stream of provider chunks.

Split out of ``client.py`` purely to keep that file under the 400-line gate — this
module owns none of the transport, only the accumulation: joining content deltas,
reassembling fragmented tool calls, and enforcing the wall-clock deadline while doing
it. It has no import on ``client.py``: the exception it raises when the deadline is
exceeded is handed in by the caller as ``deadline_exc``, so the two files can never
form an import cycle.

## Why the deadline lives HERE, not just as a bigger read timeout

``httpx``'s read timeout (``core.config.llm_timeout_s``) fires only when the SOCKET
goes silent. OpenRouter keeps a long generation's socket busy with keepalive bytes, so
a slow provider can hold a call open for many minutes without ever tripping it —
measured, one coach question ran 594 s across 3 calls under a supposed 60 s cap.
Streaming does not fix that by itself; checking the wall clock on every chunk does,
because a chunk (keepalive or real) is exactly what makes the read timeout blind to
this failure in the first place.

## Why :func:`accumulate`'s own check is not enough on its own

That check runs only when a chunk ARRIVES. OpenRouter's keepalives during a queued or
prefilling request are SSE COMMENT lines (``: OPENROUTER PROCESSING``), and the
``openai`` SDK's decoder drops comments before they ever become a chunk — so a request
stuck in that pre-first-token phase sends bytes (the read timeout stays quiet) while
never once entering :func:`accumulate`'s loop (its own check never runs either). That
is exactly the 594 s failure this module exists to close, just before the first token
rather than during generation. :func:`watchdog_accumulate` is the backstop: a real
``threading.Timer`` running alongside the (possibly indefinitely blocked) iteration,
closing the stream out of band when the deadline fires so the blocked read raises.
"""

from __future__ import annotations

import threading
import time
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ToolCallFunction:
    """The ``function`` half of one streamed tool call, joined across fragments."""

    name: str = ""
    arguments: str = ""


@dataclass
class ToolCall:
    """One tool call in the shape every caller already reads off a non-streamed
    response: ``.id``, ``.function.name``, ``.function.arguments``
    (``coach_loop._run_tools`` / ``_assistant_tool_message``)."""

    id: str = ""
    type: str = "function"
    function: ToolCallFunction = field(default_factory=ToolCallFunction)


@dataclass
class AccumulatedResponse:
    """Everything one completion produced, folded out of its chunk stream."""

    text: str
    tool_calls: list[ToolCall]
    finish_reason: str | None
    usage_raw: Any | None


def accumulate(
    chunks: Iterable[Any],
    *,
    deadline_s: float,
    deadline_exc: type[Exception],
    clock: Callable[[], float] | None = None,
) -> AccumulatedResponse:
    """Consume ``chunks`` into one :class:`AccumulatedResponse`, or raise ``deadline_exc``.

    ``clock`` is checked on every chunk, not just once at the end — a keepalive-fed
    stream never goes silent, so between-chunks is the only place a wall-clock bound
    can be enforced at all. Exceeding it closes the stream before raising, so the
    connection is not left open behind the exception.

    Defaulted to ``None`` and resolved to ``time.monotonic`` INSIDE the call, not as a
    parameter default — a default is bound once, at import time, so a test that
    monkeypatches ``client_stream.time.monotonic`` afterward would silently patch
    nothing were it bound the other way.
    """
    clock = clock or time.monotonic
    started = clock()
    text_parts: list[str] = []
    builders: dict[int, ToolCall] = {}
    finish_reason: str | None = None
    usage_raw: Any | None = None
    for chunk in chunks:
        if clock() - started > deadline_s:
            _close(chunks)
            raise deadline_exc(f"LLM completion exceeded its {deadline_s:.0f}s wall-clock deadline")
        choices = getattr(chunk, "choices", None)
        if choices:
            choice = choices[0]
            delta = getattr(choice, "delta", None)
            if delta is not None:
                content = getattr(delta, "content", None)
                if content:
                    text_parts.append(content)
                _merge_tool_calls(builders, getattr(delta, "tool_calls", None))
            reason = getattr(choice, "finish_reason", None)
            if reason:
                finish_reason = reason
        usage = getattr(chunk, "usage", None)
        if usage is not None:
            usage_raw = usage
    ordered_calls = [builders[i] for i in sorted(builders)]
    return AccumulatedResponse(
        text="".join(text_parts),
        tool_calls=ordered_calls,
        finish_reason=finish_reason,
        usage_raw=usage_raw,
    )


def _merge_tool_calls(builders: dict[int, ToolCall], deltas: Any) -> None:
    """Fold one chunk's ``delta.tool_calls`` fragments into their running builders.

    Keyed by ``index`` — the field the API uses to say which call a fragment belongs
    to, because one round can request several tools and their fragments interleave in
    the stream. ``id``/``name``/``arguments`` all concatenate: only ``arguments``
    reliably arrives in pieces, but treating the three alike costs nothing and survives
    a provider that fragments differently.
    """
    if not deltas:
        return
    for piece in deltas:
        call = builders.setdefault(piece.index, ToolCall())
        if getattr(piece, "id", None):
            call.id += piece.id
        fn = getattr(piece, "function", None)
        if fn is None:
            continue
        if getattr(fn, "name", None):
            call.function.name += fn.name
        if getattr(fn, "arguments", None):
            call.function.arguments += fn.arguments


def _close(chunks: Any) -> None:
    """Best-effort close of the underlying stream — never raise doing it.

    Tries the stream's own ``close()`` first (the ``openai`` SDK's ``Stream`` object
    has one); falls back to ``.response.close()`` (the wrapped ``httpx.Response``) for
    anything that only exposes that. Either closes the real connection a blocked
    ``next()`` is waiting on.
    """
    close = getattr(chunks, "close", None)
    if callable(close):
        close()
        return
    response = getattr(chunks, "response", None)
    response_close = getattr(response, "close", None) if response is not None else None
    if callable(response_close):
        response_close()


class _Watchdog:
    """A real wall-clock timer that closes ``stream`` if it fires before cancelled.

    Runs alongside the iteration in a background thread — the ONE thing that can
    interrupt a ``next()`` blocked on a pre-first-token phase that never yields a
    chunk at all (module docstring). ``expired`` is read by :func:`watchdog_accumulate`
    to tell "the timer closed this out from under us" apart from any other reason the
    iteration might raise.
    """

    def __init__(self, stream: Any, deadline_s: float) -> None:
        self._stream = stream
        self.expired = False
        self._timer = threading.Timer(deadline_s, self._expire)
        self._timer.daemon = True  # never blocks process shutdown

    def _expire(self) -> None:
        self.expired = True
        _close(self._stream)

    def __enter__(self) -> _Watchdog:
        self._timer.start()
        return self

    def __exit__(self, *_exc_info: object) -> None:
        self._timer.cancel()  # always — success or failure, this run is over either way


def watchdog_accumulate(
    chunks: Any,
    *,
    deadline_s: float,
    deadline_exc: type[Exception],
) -> AccumulatedResponse:
    """:func:`accumulate`, backstopped by :class:`_Watchdog` for the gap that function
    cannot close on its own: a stream that never yields a first chunk to check the
    clock on. Any exception raised WHILE the watchdog has fired is relabelled
    ``deadline_exc``; anything else propagates untouched, so a genuine provider error
    mid-stream is never misreported as a timeout.
    """
    watchdog = _Watchdog(chunks, deadline_s)
    try:
        with watchdog:
            return accumulate(chunks, deadline_s=deadline_s, deadline_exc=deadline_exc)
    except deadline_exc:
        raise  # accumulate's own per-chunk check already raised the right thing
    except Exception as exc:
        if watchdog.expired:
            raise deadline_exc(
                f"LLM completion exceeded its {deadline_s:.0f}s wall-clock deadline "
                "(no chunk arrived to trip the per-chunk check)"
            ) from exc
        raise
