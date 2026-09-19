"""Streamed-completion assembly — content deltas, tool calls, usage, the deadline.

`OpenRouterClient.complete` now makes every call with ``stream=True`` and folds the
chunk stream back into one `ChatResponse` via `client_stream.watchdog_accumulate`.
Split out of `test_client.py` purely to keep both files under the 400-line gate; the
no-network fakes are shared (`_client_fakes.py`).

The core defect this streaming change fixes: a non-streaming call's ``httpx`` read
timeout (``llm_timeout_s``) only fires when the socket goes silent, and OpenRouter's
keepalive bytes during a long generation mean it never is — measured, one coach
question ran 594 s across 3 calls under a supposed 60 s cap. Two bounds close it:

* `test_a_stream_slower_than_the_deadline_raises_and_is_recorded` — the CHEAP path,
  `client_stream.accumulate`'s own per-chunk clock check (works with a fake clock, no
  real waiting).
* `test_a_stream_with_no_chunks_at_all_is_closed_by_the_watchdog_and_reads_as_a_
  deadline` — the gap that check cannot reach: a request stuck queued/prefilling sends
  OpenRouter's keepalives as SSE COMMENT lines, which the ``openai`` SDK's decoder
  drops before they ever become a chunk, so NO chunk arrives to trip the check. Only a
  real `threading.Timer` (`client_stream._Watchdog`) can interrupt that blocked read —
  this test uses a short real deadline (~0.05 s), not a mocked one.
"""

from __future__ import annotations

import itertools
import logging
import os
import threading
import time
from types import SimpleNamespace
from typing import Any

import pytest
from tests.insights._client_fakes import _chunk, _client_with_fake, _tool_call_delta, _usage_chunk

from healthee.core.config import get_settings
from healthee.insights import client as client_module
from healthee.insights import transport_health
from healthee.insights.client import (
    LLMDeadlineExceeded,
    OpenRouterClient,
    default_model,
    get_client,
)


def test_content_deltas_are_joined_into_one_string() -> None:
    chunks = [
        _chunk(content="The "),
        _chunk(content="answer "),
        _chunk(content="is 42.", finish_reason="stop"),
        _usage_chunk(None),
    ]
    client, _ = _client_with_fake(chunks=chunks)
    response = client.complete([{"role": "user", "content": "x"}])
    assert response.text == "The answer is 42."


def test_tool_call_fragments_assemble_into_one_call_with_full_arguments() -> None:
    """``arguments`` streams in pieces; the whole point is the joined string parses."""
    chunks = [
        _chunk(tool_calls=[_tool_call_delta(0, call_id="call_1", name="get_sleep")]),
        _chunk(tool_calls=[_tool_call_delta(0, arguments='{"da')]),
        _chunk(
            tool_calls=[_tool_call_delta(0, arguments='te": "today"}')],
            finish_reason="tool_calls",
        ),
        _usage_chunk(None),
    ]
    client, _ = _client_with_fake(chunks=chunks)
    response = client.complete([{"role": "user", "content": "x"}])
    assert response.tool_calls is not None and len(response.tool_calls) == 1
    call = response.tool_calls[0]
    assert call.id == "call_1"
    assert call.function.name == "get_sleep"
    assert call.function.arguments == '{"date": "today"}'


def test_two_interleaved_tool_calls_assemble_separately() -> None:
    """One round can request several tools; their fragments interleave by ``index``."""
    chunks = [
        _chunk(tool_calls=[_tool_call_delta(0, call_id="call_a", name="get_sleep")]),
        _chunk(tool_calls=[_tool_call_delta(1, call_id="call_b", name="get_steps")]),
        _chunk(tool_calls=[_tool_call_delta(0, arguments="{}")]),
        _chunk(tool_calls=[_tool_call_delta(1, arguments="{}")], finish_reason="tool_calls"),
        _usage_chunk(None),
    ]
    client, _ = _client_with_fake(chunks=chunks)
    response = client.complete([{"role": "user", "content": "x"}])
    assert response.tool_calls is not None
    assert [c.id for c in response.tool_calls] == ["call_a", "call_b"]
    assert [c.function.name for c in response.tool_calls] == ["get_sleep", "get_steps"]
    assert all(c.function.arguments == "{}" for c in response.tool_calls)


def test_on_text_receives_the_cumulative_text_on_every_content_delta() -> None:
    chunks = [
        _chunk(content="The "),
        _chunk(content="answer "),
        _chunk(content="is 42.", finish_reason="stop"),
        _usage_chunk(None),
    ]
    client, _ = _client_with_fake(chunks=chunks)
    seen: list[str] = []
    response = client.complete([{"role": "user", "content": "x"}], on_text=seen.append)
    assert seen == ["The ", "The answer ", "The answer is 42."]
    assert response.text == "The answer is 42."


def test_on_text_is_not_called_for_a_tool_only_chunk() -> None:
    """A tool-call fragment carries no content delta — nothing to stream as a draft."""
    chunks = [
        _chunk(tool_calls=[_tool_call_delta(0, call_id="call_1", name="get_sleep")]),
        _chunk(tool_calls=[_tool_call_delta(0, arguments="{}")], finish_reason="tool_calls"),
        _usage_chunk(None),
    ]
    client, _ = _client_with_fake(chunks=chunks)
    seen: list[str] = []
    client.complete([{"role": "user", "content": "x"}], on_text=seen.append)
    assert seen == []


def test_a_raising_on_text_does_not_break_the_completion(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Mirrors `pipeline.emit_event`: a broken progress observer must never cost the
    answer it is only watching."""
    chunks = [_chunk(content="ok", finish_reason="stop"), _usage_chunk(None)]
    client, _ = _client_with_fake(chunks=chunks)

    def exploding(_text: str) -> None:
        raise RuntimeError("a client watching this stream just vanished")

    with caplog.at_level(logging.ERROR):
        response = client.complete([{"role": "user", "content": "x"}], on_text=exploding)
    assert response.text == "ok"
    assert any("on_text observer raised" in r.message for r in caplog.records)


def test_usage_from_the_final_chunk_populates_every_field_including_cost() -> None:
    usage = SimpleNamespace(
        prompt_tokens=500,
        completion_tokens=120,
        completion_tokens_details=SimpleNamespace(reasoning_tokens=40),
        prompt_tokens_details=SimpleNamespace(cached_tokens=300),
        cost=0.0231,
    )
    chunks = [_chunk(content="ok", finish_reason="stop"), _usage_chunk(usage)]
    client, _ = _client_with_fake(chunks=chunks)
    response = client.complete([{"role": "user", "content": "x"}])
    assert response.usage is not None
    assert response.usage.prompt_tokens == 500
    assert response.usage.completion_tokens == 120
    assert response.usage.reasoning_tokens == 40
    assert response.usage.cached_prompt_tokens == 300
    assert response.usage.cost == 0.0231


def test_finish_reason_length_still_triggers_the_truncation_warning_when_streamed(
    caplog: pytest.LogCaptureFixture,
) -> None:
    chunks = [_chunk(content="cut off mid-", finish_reason="length"), _usage_chunk(None)]
    client, _ = _client_with_fake(chunks=chunks)
    with caplog.at_level(logging.WARNING):
        client.complete([{"role": "user", "content": "x"}])
    warnings = "\n".join(r.getMessage() for r in caplog.records if r.levelno >= logging.WARNING)
    assert "TRUNCATED" in warnings


def test_the_request_carries_streaming_and_provider_billed_cost_fields() -> None:
    """The three fields this whole change adds to the wire, in one place."""
    client, fake = _client_with_fake()
    client.complete([{"role": "user", "content": "x"}])
    kwargs = fake.chat.completions.kwargs
    assert kwargs is not None
    assert kwargs["stream"] is True
    assert kwargs["stream_options"] == {"include_usage": True}
    assert kwargs["extra_body"]["usage"] == {"include": True}


def test_a_stream_slower_than_the_deadline_raises_and_is_recorded(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A keepalive-fed stream never trips the read timeout — only the wall clock can.

    The chunks arrive "instantly" (no real sleep); the clock is what moves. Each
    `time.monotonic()` call advances by a huge stride, so the very first deadline
    check inside `client_stream.accumulate` sees the deadline blown, regardless of
    exactly how many earlier calls (`complete`'s own `started`, `accumulate`'s own
    `started`) already consumed a tick.
    """
    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    # Both tiers too: the settings guard refuses a key with blank model ids, and CI has
    # no .env to supply them (locally one does, which hid this).
    monkeypatch.setenv("DEFAULT_MODEL", "vendor-x/cheap-tier-1")
    monkeypatch.setenv("COACH_MODEL", "vendor-x/strong-tier-1")
    monkeypatch.setenv("LLM_DEADLINE_S", "120")
    get_settings.cache_clear()
    ticking = itertools.count(0.0, 1_000_000.0)
    monkeypatch.setattr(client_module.client_stream.time, "monotonic", lambda: next(ticking))
    chunks = [_chunk(content="partial"), _chunk(content="more"), _usage_chunk(None)]
    client, fake = _client_with_fake(chunks=chunks)
    try:
        with pytest.raises(LLMDeadlineExceeded):
            client.complete([{"role": "user", "content": "x"}])
        assert fake.chat.completions.stream is not None
        assert fake.chat.completions.stream.closed is True
        snapshot = transport_health.snapshot()
        assert snapshot.consecutive_failures == 1
        assert snapshot.last_error_kind == transport_health.TIMEOUT
    finally:
        get_settings.cache_clear()


class _BlockingStream:
    """What a request stuck queued/prefilling looks like: `__next__` never returns a
    chunk on its own — only `close()` (the watchdog's job) unblocks it, the same way
    closing a real connection makes a blocked socket read raise.

    No real sleep: the block is a `threading.Event`, not time passing.
    """

    def __init__(self) -> None:
        self._event = threading.Event()
        self.closed = False

    def __iter__(self) -> _BlockingStream:
        return self

    def __next__(self) -> Any:
        self._event.wait()  # only close() sets this
        raise RuntimeError("stream closed")

    def close(self) -> None:
        self.closed = True
        self._event.set()


def _client_with_sdk_stream(stream: Any) -> OpenRouterClient:
    client = OpenRouterClient()
    fake = SimpleNamespace(
        chat=SimpleNamespace(completions=SimpleNamespace(create=lambda **_kw: stream))
    )
    client._client = lambda: fake  # type: ignore[method-assign]
    return client


def test_a_stream_with_no_chunks_at_all_is_closed_by_the_watchdog_and_reads_as_a_deadline(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """THE gap: a keepalive that never becomes a chunk defeats the cheap per-chunk
    check above, because that check only runs when a chunk arrives. A short REAL
    deadline (~0.05 s) proves the watchdog thread — not a mocked clock — is what
    interrupts the blocked read here."""
    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    # Both tiers too: the settings guard refuses a key with blank model ids, and CI has
    # no .env to supply them (locally one does, which hid this).
    monkeypatch.setenv("DEFAULT_MODEL", "vendor-x/cheap-tier-1")
    monkeypatch.setenv("COACH_MODEL", "vendor-x/strong-tier-1")
    monkeypatch.setenv("LLM_DEADLINE_S", "0.05")
    get_settings.cache_clear()
    stream = _BlockingStream()
    client = _client_with_sdk_stream(stream)
    try:
        with pytest.raises(LLMDeadlineExceeded):
            client.complete([{"role": "user", "content": "x"}])
        assert stream.closed is True
        snapshot = transport_health.snapshot()
        assert snapshot.consecutive_failures == 1
        assert snapshot.last_error_kind == transport_health.TIMEOUT
    finally:
        get_settings.cache_clear()


def test_the_watchdog_timer_is_cancelled_on_the_success_path(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A fast stream must not carry a live timer past its own return — proven by
    waiting LONGER than the deadline afterward and finding nothing closed."""
    monkeypatch.setenv("LLM_DEADLINE_S", "0.05")
    get_settings.cache_clear()
    chunks = [_chunk(content="ok", finish_reason="stop"), _usage_chunk(None)]
    client, fake = _client_with_fake(chunks=chunks)
    try:
        response = client.complete([{"role": "user", "content": "x"}])
        assert response.text == "ok"
        time.sleep(0.15)  # well past the 0.05s deadline
        assert fake.chat.completions.stream is not None
        assert fake.chat.completions.stream.closed is False
    finally:
        get_settings.cache_clear()


def test_a_non_deadline_exception_mid_stream_propagates_as_itself(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Only a raise that happens WHILE the watchdog has fired gets relabelled a
    deadline; a genuine provider error mid-stream — the deadline never having fired —
    must reach the caller unchanged, not be misreported as a timeout."""
    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    # Both tiers too: the settings guard refuses a key with blank model ids, and CI has
    # no .env to supply them (locally one does, which hid this).
    monkeypatch.setenv("DEFAULT_MODEL", "vendor-x/cheap-tier-1")
    monkeypatch.setenv("COACH_MODEL", "vendor-x/strong-tier-1")
    monkeypatch.setenv("LLM_DEADLINE_S", "120")  # generous: the watchdog never fires
    get_settings.cache_clear()

    def _exploding_chunks() -> Any:
        yield _chunk(content="partial")
        raise ValueError("boom")

    client = _client_with_sdk_stream(_exploding_chunks())
    try:
        with pytest.raises(ValueError, match="boom"):
            client.complete([{"role": "user", "content": "x"}])
    finally:
        get_settings.cache_clear()


# ── one real call, opt-in only (never run by CI or by default) ───────────────


@pytest.mark.skipif(
    os.environ.get("HEALTHEE_LIVE_LLM") != "1",
    reason="hits the real OpenRouter API and spends real money — opt in with HEALTHEE_LIVE_LLM=1",
)
def test_live_one_real_completion_reports_text_and_a_provider_billed_cost() -> None:
    """The only test in this file that touches the network.

    Proves the streaming transport and ``usage.cost`` work against the REAL API, not
    just the fakes above — every other test here could pass while OpenRouter's actual
    streamed shape had quietly drifted from what the fakes assume. Run deliberately,
    on a key with a small credit limit (``EVAL_OPENROUTER_API_KEY`` per
    ``apps/server/.env.example``), never as part of the normal suite.
    """
    response = get_client().complete(
        [{"role": "user", "content": "Reply with exactly one word: pong"}],
        model=default_model(),
    )
    assert response.text.strip() != ""
    assert response.usage is not None
    assert response.usage.cost is not None
