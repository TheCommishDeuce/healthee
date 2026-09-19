"""``api/coach_stream``'s pure transport pieces — no DB, no network, no real sleep.

The queue-draining generator, the SSE frame encoder, the timeout classifier, and the
worker's refund/terminal-event logic are all plain functions over a
``queue.Queue``/dataclasses — this exercises them directly. The full HTTP path (real
SSE framing over ``TestClient``, the real ledger) is
``tests/premium/test_coach_stream.py``; the event EMISSION order is
``tests/insights/test_coach_progress.py``.
"""

from __future__ import annotations

import json
import queue
from collections.abc import Callable
from types import SimpleNamespace
from typing import Any, cast
from uuid import uuid4

import httpx
import openai
import pytest
from fastapi import Request

from healthee.api import coach_stream
from healthee.core.supabase_auth import RequestUser
from healthee.insights.coach import CoachResult, coach_reply_payload
from healthee.insights.pipeline import NOOP_EVENT

# ── the SSE frame encoder ─────────────────────────────────────────────────────


def test_sse_frames_one_event_and_one_line_of_json() -> None:
    frame = coach_stream._sse("stage", {"stage": "context", "round": 0, "detail": None})
    assert frame == b'event: stage\ndata: {"stage":"context","round":0,"detail":null}\n\n'


# ── the timeout classifier ─────────────────────────────────────────────────────


def test_a_plain_exception_is_not_a_timeout() -> None:
    assert coach_stream._is_timeout(RuntimeError("boom")) is False


def test_a_stdlib_timeout_error_is_a_timeout() -> None:
    assert coach_stream._is_timeout(TimeoutError("slow")) is True


def test_the_llm_deadline_exceeded_subclass_is_a_timeout() -> None:
    from healthee.insights.client import LLMDeadlineExceeded

    assert coach_stream._is_timeout(LLMDeadlineExceeded("deadline")) is True


def test_openai_api_timeout_error_is_a_timeout_though_it_is_not_a_stdlib_one() -> None:
    exc = openai.APITimeoutError(request=httpx.Request("POST", "https://example.invalid"))
    assert not isinstance(exc, TimeoutError)  # the fact this module works around
    assert coach_stream._is_timeout(exc) is True


# ── the queue-draining generator: keepalive, then the terminal frame ─────────


def test_the_generator_emits_a_keepalive_comment_while_the_queue_is_idle() -> None:
    q: queue.Queue[Any] = queue.Queue()
    gen = coach_stream._drain(q, keepalive_s=0.02)
    assert next(gen) == b": keepalive\n\n"
    assert next(gen) == b": keepalive\n\n"
    q.put({"stage": "context", "round": 0, "detail": None})
    assert next(gen) == coach_stream._sse("stage", {"stage": "context", "round": 0, "detail": None})
    q.put(coach_stream._Terminal("answer", {"ok": True}))
    assert next(gen) == coach_stream._sse("answer", {"ok": True})
    with pytest.raises(StopIteration):
        next(gen)


def test_the_generator_stops_at_the_first_terminal_event_only() -> None:
    """A stage event never ends the stream; only a `_Terminal` does."""
    q: queue.Queue[Any] = queue.Queue()
    q.put({"stage": "thinking", "round": 1, "detail": None})
    q.put({"stage": "checking", "round": 1, "detail": None})
    q.put(coach_stream._Terminal("error", {"status": 500, "message": "x"}))
    frames = list(coach_stream._drain(q, keepalive_s=0.02))
    assert len(frames) == 3
    assert frames[-1] == coach_stream._sse("error", {"status": 500, "message": "x"})


# ── the worker: refund guarantees + the terminal event it produces ───────────


def _request_and_user() -> tuple[Request, RequestUser]:
    """Fakes shaped like the two real types — enough for ``_run_worker``, which only
    reads ``request.state`` and ``user.id``/``user.timezone``."""
    request = cast(Request, SimpleNamespace(state=SimpleNamespace()))
    user = cast(RequestUser, SimpleNamespace(id=uuid4(), timezone="UTC"))
    return request, user


def _run_worker_capture(
    monkeypatch: pytest.MonkeyPatch, run_coach_fn: Callable[..., Any]
) -> tuple[list[str], Any]:
    refunds: list[str] = []
    monkeypatch.setattr(coach_stream, "run_coach", run_coach_fn)
    monkeypatch.setattr(coach_stream.gate, "refund_ai_use", lambda *a: refunds.append("refund"))
    q: queue.Queue[Any] = queue.Queue()
    request, user = _request_and_user()
    coach_stream._run_worker(q, request, user, [], None)
    return refunds, q.get_nowait()


def test_a_clean_answer_is_not_refunded(monkeypatch: pytest.MonkeyPatch) -> None:
    result = CoachResult(reply="fine", refused=False, validated=True, answered=True)
    refunds, terminal = _run_worker_capture(monkeypatch, lambda *a, **k: result)
    assert refunds == []
    assert terminal.event == "answer"
    assert terminal.data == coach_reply_payload(result)


@pytest.mark.parametrize(
    "result_kwargs",
    [
        {"refused": True, "validated": False},
        {"validated": False},
        {"answered": False},
    ],
)
def test_a_turn_that_delivered_nothing_is_refunded(
    monkeypatch: pytest.MonkeyPatch, result_kwargs: dict
) -> None:
    result = CoachResult(reply="x", **result_kwargs)
    refunds, terminal = _run_worker_capture(monkeypatch, lambda *a, **k: result)
    assert refunds == ["refund"]
    assert terminal.event == "answer"


def test_an_exception_is_refunded_and_reported_as_a_500(monkeypatch: pytest.MonkeyPatch) -> None:
    def explode(*_a: object, **_k: object) -> None:
        raise RuntimeError("boom")

    refunds, terminal = _run_worker_capture(monkeypatch, explode)
    assert refunds == ["refund"]
    assert terminal.event == "error"
    assert terminal.data == {"status": 500, "message": "the coach turn failed"}


def test_a_timeout_is_refunded_and_reported_as_a_504(monkeypatch: pytest.MonkeyPatch) -> None:
    def timed_out(*_a: object, **_k: object) -> None:
        raise TimeoutError("slow")

    refunds, terminal = _run_worker_capture(monkeypatch, timed_out)
    assert refunds == ["refund"]
    assert terminal.event == "error"
    assert terminal.data == {"status": 504, "message": "the coach timed out"}


def test_the_worker_relays_the_stage_events_run_coach_emits(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`on_event=q.put` — the same queue the stage events and the terminal event share."""

    def scripted(
        *_a: object, on_event: Callable[[dict], None] = NOOP_EVENT, **_k: object
    ) -> CoachResult:
        on_event({"stage": "context", "round": 0, "detail": None})
        on_event({"stage": "thinking", "round": 1, "detail": None})
        return CoachResult(reply="ok", validated=True)

    monkeypatch.setattr(coach_stream, "run_coach", scripted)
    monkeypatch.setattr(coach_stream.gate, "refund_ai_use", lambda *a: None)
    q: queue.Queue[Any] = queue.Queue()
    request, user = _request_and_user()
    coach_stream._run_worker(q, request, user, [], None)
    first = q.get_nowait()
    second = q.get_nowait()
    terminal = q.get_nowait()
    assert first == {"stage": "context", "round": 0, "detail": None}
    assert second == {"stage": "thinking", "round": 1, "detail": None}
    assert isinstance(terminal, coach_stream._Terminal)
    assert terminal.event == "answer"


def test_sse_payload_is_valid_one_line_json() -> None:
    frame = coach_stream._sse("answer", {"reply": "hi\nthere"})
    line = frame.decode().splitlines()[1]
    assert line.startswith("data: ")
    assert json.loads(line.removeprefix("data: ")) == {"reply": "hi\nthere"}
