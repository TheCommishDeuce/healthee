"""SSE machinery for ``POST /api/coach/stream`` — the streaming twin of ``/api/coach``.

Kept out of ``routers/coach.py`` so the router body stays a few lines (standards §2:
"routers are thin"). Everything here is transport: encode one stage/answer/error event
as one SSE frame, run ``run_coach`` on a worker thread that pushes events into a
queue, and drain that queue with a keepalive comment while the worker is between
events.

## Why a worker thread and not ``await run_coach(...)``

``run_coach`` and everything under it (the DB pool, the LLM transport) is
synchronous — standards §2 decided that once for the whole app. Calling it directly
inside the async generator would block the event loop for the whole 15-40s turn,
starving every other request this process is holding. A thread lets the async side do
nothing but drain a queue.

## The DRAFT is not the answer (the owner's 2026-09-19 call)

INTELLIGENCE section 3's "unvalidated text never ships" now names one deliberate,
documented exception: a ``draft`` event (``{"round", "text"}``) carries the coach's
answer prose as the model is still writing it — shown to the owner AS A DRAFT, muted
in the app, never as a shipped answer. It can be rewritten (a rejected candidate
starts the next round's draft from empty text) or superseded outright. Every stage
NAME besides it (``context``/``thinking``/``tool``/``checking``/``revising``) still
carries no prose at all. The one payload the gates have judged is still the terminal
``answer`` event, and it always supersedes whatever draft preceded it — see
INTELLIGENCE section 3 for the reasoning and what stays a hard guardrail regardless.

## The refund happens IN THE WORKER, before the terminal event

``api.gate.refund_ai_use`` reads ``request.state`` (set by the gate that already
charged this request) and reaches its own DB connection through the pool, which is
thread-safe by design (``core/db.py``: "the pool is the only way in"). Calling it here
— before either the ``answer`` or the ``error`` event is queued — is what makes the
refund a guarantee rather than a race: ``queue.Queue`` synchronizes on its own lock, so
the generator can only ever observe the terminal event AFTER the refund already ran on
the same thread that decided whether one was owed.

A client that disconnects mid-stream changes none of this: the model call is already
paid for and already running, so the worker runs it to completion regardless, and the
refund rule applies to whatever it produced exactly as if somebody was still watching.
"""

from __future__ import annotations

import json
import queue
import threading
from collections.abc import Iterator
from dataclasses import dataclass
from typing import Any

from fastapi import Request
from fastapi.responses import StreamingResponse

from healthee.api import gate
from healthee.core.logging import get_logger
from healthee.core.supabase_auth import RequestUser
from healthee.insights.coach import coach_reply_payload, run_coach

log = get_logger(__name__)

# At least every 10s while a round is running — the wire contract's own number, not a
# deployment knob: it is what "still working" means to a client waiting on this
# stream, not something load should tune. A module constant (rather than settings) so
# a test can override it directly without touching `core.config`.
KEEPALIVE_INTERVAL_S = 10.0

_KEEPALIVE_COMMENT = b": keepalive\n\n"

# Exception class NAMES that report 504 rather than 500 — the "the transport, not us"
# family. `TimeoutError` (stdlib) already covers `insights.client.LLMDeadlineExceeded`
# by inheritance; `openai.APITimeoutError` is checked against the installed SDK and is
# NOT a `TimeoutError` subclass, so it is named here instead of imported — the same
# duck-typed approach `insights.transport_health.classify` already uses so this module
# carries no `openai` import for the sake of one exception name.
_TIMEOUT_EXCEPTION_NAMES = frozenset({"APITimeoutError"})


def _is_timeout(exc: BaseException) -> bool:
    """Whether ``exc`` belongs to the timeout family the wire contract reports as 504."""
    return isinstance(exc, TimeoutError) or type(exc).__name__ in _TIMEOUT_EXCEPTION_NAMES


def _sse(event: str, data: dict) -> bytes:
    """One SSE frame: ``event: <name>\\ndata: <one-line json>\\n\\n``."""
    return f"event: {event}\ndata: {json.dumps(data, separators=(',', ':'))}\n\n".encode()


@dataclass(frozen=True)
class _Terminal:
    """The one thing the worker puts LAST — a stage event is a bare dict, never this."""

    event: str
    data: dict


def _run_worker(
    q: queue.Queue[Any],
    request: Request,
    user: RequestUser,
    messages: list[dict],
    topic: str | None,
) -> None:
    """Run the coach turn to completion; refund if it earned one; queue the terminal event.

    The one place outside ``pipeline.emit_event`` a broad ``except Exception`` is
    correct: whatever the turn raises must still become a terminal SSE event — nothing
    is watching this thread to convert an uncaught exception into a response — and it
    must still be LOGGED with its traceback exactly as an unhandled one is today
    (standards §Errors: never swallowed silently).
    """
    try:
        result = run_coach(messages, user.id, user.timezone, topic=topic, on_event=q.put)
    except Exception as exc:  # noqa: BLE001 — turned into the terminal event, not swallowed
        log.exception("coach stream worker failed for %s", user.id)
        gate.refund_ai_use(request, user)
        status = 504 if _is_timeout(exc) else 500
        message = "the coach timed out" if status == 504 else "the coach turn failed"
        q.put(_Terminal("error", {"status": status, "message": message}))
        return
    if result.refused or not result.validated or not result.answered:
        gate.refund_ai_use(request, user)
    q.put(_Terminal("answer", coach_reply_payload(result)))


def sse_name_and_data(event: dict) -> tuple[str, dict]:
    """What one ``on_event`` dict becomes on the wire: ``("stage", event)`` UNLESS it
    carries an ``"event"`` key of its own — today only
    ``{"event": "draft", "round", "text"}`` (``coach_loop``'s live-draft events, the
    owner's 2026-09-19 call) — in which case that key names the SSE event and the rest
    of the dict is its data.

    Extracted so ``tests/contracts/test_coach_stream_contract.py`` builds the exact same
    wire shape from a captured ``on_event`` call that ``_drain`` builds from a live
    queue item — a second, hand-kept copy of this mapping is exactly how the two would
    drift.
    """
    name = event.get("event")
    if name is None:
        return "stage", event
    return name, {k: v for k, v in event.items() if k != "event"}


def _drain(q: queue.Queue[Any], *, keepalive_s: float = KEEPALIVE_INTERVAL_S) -> Iterator[bytes]:
    """Yield one SSE frame per queued event; a keepalive comment when a round is slow.

    A :class:`_Terminal` is the last thing the worker ever queues, so this generator's
    only exit is receiving one; every other queued item is a plain ``dict`` named and
    shaped by :func:`sse_name_and_data`.
    """
    while True:
        try:
            item = q.get(timeout=keepalive_s)
        except queue.Empty:
            yield _KEEPALIVE_COMMENT
            continue
        if isinstance(item, _Terminal):
            yield _sse(item.event, item.data)
            return
        event_name, data = sse_name_and_data(item)
        yield _sse(event_name, data)


def stream_response(
    request: Request, user: RequestUser, messages: list[dict], topic: str | None
) -> StreamingResponse:
    """Start the worker and return the SSE response draining its queue.

    Called only after ``CoachUser`` has already authenticated and charged the request
    (the same dependency ``/api/coach`` takes), so everything that can fail BEFORE a
    byte ships — 401/402/422/429 — already has, on the ordinary FastAPI path, with the
    ordinary JSON body. From here on the response is always 200; a turn that raised, or
    one the honesty gates refused/could not validate, ships as ``event: error`` or an
    ``answer`` payload with ``validated: false`` — never an HTTP failure, because the
    status line already went out.
    """
    q: queue.Queue[Any] = queue.Queue()
    worker = threading.Thread(
        target=_run_worker, args=(q, request, user, messages, topic), daemon=True
    )
    worker.start()
    return StreamingResponse(
        _drain(q),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
