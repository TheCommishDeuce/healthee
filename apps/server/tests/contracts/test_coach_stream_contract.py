"""Contract for POST /api/coach/stream's SSE event schema (packages/contracts).

Every other file in this directory pins ONE JSON response; `/api/coach/stream` emits
a SEQUENCE of heterogeneous events instead, so the committed snapshot documents one
sample of each event KIND rather than one whole response — see
`packages/contracts/README.md`'s own section on this file for why.

No DB: the context/evidence build is stubbed exactly as `tests/insights/test_coach.py`
does, so this is a structural check on the WIRE FORMAT — what shape a `stage`/`draft`/
`answer`/`error` event takes — not a seeded-DB fixture test. The DB-backed, real-HTTP
version of this (real SSE framing, the real ledger) is `tests/premium/test_coach_stream.py`.
"""

from __future__ import annotations

import json
import queue
from pathlib import Path
from types import SimpleNamespace
from typing import Any, cast
from uuid import uuid4

import pytest
from fastapi import Request
from tests.contracts.shape import assert_conforms
from tests.insights._coach_stub import CoachStub, tool_call, tool_turn, valid_turn

from healthee.api import coach_stream
from healthee.core.supabase_auth import RequestUser
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.insights import coach, coach_thread, coach_tools

_SNAPSHOT = (
    Path(__file__).resolve().parents[4]
    / "packages"
    / "contracts"
    / "snapshots"
    / "coach_stream_events.json"
)


@pytest.fixture(autouse=True)
def _stub_context(monkeypatch: pytest.MonkeyPatch) -> None:
    """Skip the DB-backed context/evidence build — see `test_coach.py` for why."""
    monkeypatch.setattr(
        coach,
        "_initial_messages",
        lambda history, q, user_id, tz, days, topic=None: [
            {"role": "system", "content": f"CONTEXT{coach_thread.topic_block(topic)}"},
            *history,
        ],
    )


def _snapshot_events() -> list[dict]:
    return json.loads(_SNAPSHOT.read_text())


def _as_event(event: dict) -> dict:
    """One captured `on_event` dict, named and shaped exactly as `coach_stream._drain`
    would frame it on the wire (`coach_stream.sse_name_and_data`) — a `stage` dict, or a
    `{"event": "draft", ...}` dict naming itself."""
    name, data = coach_stream.sse_name_and_data(event)
    return {"event": name, "data": data}


def test_a_tool_using_turns_events_conform_to_the_committed_schema(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The `context`/`thinking`/`tool`/`checking` stage shapes, the `draft` shape (the
    content round's final-flush draft, since `CoachStub` here answers in one piece
    rather than through `on_text`), and the `answer` shape."""
    monkeypatch.setattr(coach_tools, "execute_tool", lambda name, args, uid, tz: {"avg": 42.0})
    stub = CoachStub(
        [tool_turn(tool_call("c1", "query_metric", '{"metric": "hrv_sleep_avg"}')), valid_turn()]
    )
    captured: list[dict] = []
    result = coach.run_coach(
        [{"role": "user", "content": "how am I doing?"}],
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        client=stub,
        on_event=lambda event: captured.append(_as_event(event)),
    )
    assert any(e["event"] == "draft" for e in captured)
    live = [*captured, {"event": "answer", "data": coach.coach_reply_payload(result)}]
    assert_conforms(live, _snapshot_events(), "root")


def test_a_revised_then_accepted_turns_events_conform_too() -> None:
    """The `revising` stage — a shape identical to every other stage, asserted anyway.

    Checked against the STAGE samples only: the answer payload's own shape (which
    varies with which metrics a turn happened to read) is already proven by the
    tool-using test above, and re-checking it here would just be a second, weaker
    assertion about the same `coach_reply_payload` shape. `draft` events are captured
    too (a rejected candidate still streams one) but filtered out here for the same
    reason — their own shape is already proven by the test above.
    """
    from tests.insights._coach_stub import claim_turn

    stub = CoachStub([claim_turn("This is great", ["not_a_real_note"]), valid_turn()])
    captured: list[dict] = []
    coach.run_coach(
        [{"role": "user", "content": "how am I doing?"}],
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        client=stub,
        on_event=lambda event: captured.append(_as_event(event)),
    )
    stages = [e for e in captured if e["event"] == "stage"]
    assert any(e["data"]["stage"] == "revising" for e in stages)
    stage_samples = [e for e in _snapshot_events() if e["event"] == "stage"]
    assert_conforms(stages, stage_samples, "root")


def test_an_error_events_shape_conforms_to_the_committed_schema(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`api/coach_stream`'s own terminal error event — the third documented shape."""

    def explode(*_a: object, **_k: object) -> None:
        raise RuntimeError("boom")

    monkeypatch.setattr(coach_stream, "run_coach", explode)
    monkeypatch.setattr(coach_stream.gate, "refund_ai_use", lambda *a: None)
    q: queue.Queue[Any] = queue.Queue()
    request = cast(Request, SimpleNamespace(state=SimpleNamespace()))
    user = cast(RequestUser, SimpleNamespace(id=uuid4(), timezone="UTC"))
    coach_stream._run_worker(q, request, user, [], None)
    terminal = q.get_nowait()
    live = [{"event": terminal.event, "data": terminal.data}]
    assert_conforms(live, _snapshot_events(), "root")
