"""``run_coach``'s progress hook — no DB, no network (mirrors ``test_coach.py``).

The coach's streaming twin (``api/coach_stream.py``) needs live progress events; this
proves the EMISSION side of that contract — what fires, in what order, with what
payload — independent of the queue/thread/SSE machinery that consumes it (covered by
``tests/insights/test_coach_stream.py``, which needs the DB).
"""

from __future__ import annotations

import logging

import pytest
from tests.insights._coach_stub import (
    VALID_ANSWER_JSON,
    VALID_REPLY,
    CoachStub,
    claim_turn,
    streamed,
    tool_call,
    tool_turn,
    valid_turn,
)

from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.insights import coach, coach_loop, coach_thread, coach_tools, pipeline


@pytest.fixture(autouse=True)
def _stub_context(monkeypatch: pytest.MonkeyPatch) -> None:
    """Skip the DB-backed context/evidence build — see ``test_coach.py`` for why."""
    monkeypatch.setattr(
        coach,
        "_initial_messages",
        lambda history, q, user_id, tz, days, topic=None: [
            {"role": "system", "content": f"CONTEXT{coach_thread.topic_block(topic)}"},
            *history,
        ],
    )


def _ask(text: str) -> list[dict]:
    return [{"role": "user", "content": text}]


def _run_with_events(text: str, **kwargs) -> tuple[coach.CoachResult, list[dict]]:
    events: list[dict] = []
    result = coach.run_coach(
        _ask(text), SENTINEL_USER_ID, SENTINEL_TZ, on_event=events.append, **kwargs
    )
    return result, events


def _stage_events(events: list[dict]) -> list[dict]:
    """Every STAGE event, filtering out `draft` events — those carry no `stage` key
    at all (`{"event": "draft", "round", "text"}`); the draft-emission tests further
    down in this file assert on them directly."""
    return [e for e in events if "stage" in e]


def _stages(events: list[dict]) -> list[str]:
    return [e["stage"] for e in _stage_events(events)]


# ── the tool-using turn: context, thinking, tool, thinking, checking ─────────


def test_a_tool_using_turn_emits_the_documented_stage_order(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(coach_tools, "execute_tool", lambda name, args, uid, tz: {"avg": 42.0})
    stub = CoachStub(
        [
            tool_turn(tool_call("c1", "query_metric", '{"metric": "hrv_sleep_avg"}')),
            valid_turn(),
        ]
    )
    result, events = _run_with_events("what's my HRV?", client=stub)
    assert result.validated is True
    assert _stages(events) == ["context", "thinking", "tool", "thinking", "checking"]


def test_the_tool_event_names_the_tool_and_shares_its_rounds_thinking_round(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(coach_tools, "execute_tool", lambda name, args, uid, tz: {"avg": 42.0})
    stub = CoachStub(
        [
            tool_turn(tool_call("c1", "query_metric", '{"metric": "hrv_sleep_avg"}')),
            valid_turn(),
        ]
    )
    _, events = _run_with_events("what's my HRV?", client=stub)
    thinking = [e for e in _stage_events(events) if e["stage"] == "thinking"]
    tool_event = next(e for e in _stage_events(events) if e["stage"] == "tool")
    assert tool_event["detail"] == "query_metric"
    assert tool_event["round"] == thinking[0]["round"] == 1
    assert thinking[1]["round"] == 2


def test_multiple_tools_in_one_round_each_get_their_own_tool_event(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(coach_tools, "execute_tool", lambda name, args, uid, tz: {"ok": True})
    stub = CoachStub(
        [
            tool_turn(
                tool_call("c1", "query_metric", '{"metric": "hrv_sleep_avg"}'),
                tool_call("c2", "sleep_consistency", "{}"),
            ),
            valid_turn(),
        ]
    )
    _, events = _run_with_events("how am I sleeping and recovering?", client=stub)
    tool_events = [e for e in _stage_events(events) if e["stage"] == "tool"]
    assert [e["detail"] for e in tool_events] == ["query_metric", "sleep_consistency"]
    assert {e["round"] for e in tool_events} == {1}


# ── revising: a rejected candidate, then a shipped one ───────────────────────


def test_revising_appears_between_two_checking_events_when_a_retry_succeeds() -> None:
    bad = claim_turn("This is great", ["not_a_real_note"])
    stub = CoachStub([bad, valid_turn()])
    result, events = _run_with_events("how am I doing?", client=stub)
    assert result.validated is True
    assert _stages(events) == [
        "context",
        "thinking",
        "checking",
        "revising",
        "thinking",
        "checking",
    ]
    checks = [e for e in _stage_events(events) if e["stage"] == "checking"]
    revise = [e for e in _stage_events(events) if e["stage"] == "revising"]
    assert checks[0]["round"] == revise[0]["round"] == 1
    assert checks[1]["round"] == 2


def test_a_clean_first_answer_never_emits_revising() -> None:
    _, events = _run_with_events("how am I doing?", client=CoachStub([valid_turn()]))
    assert "revising" not in _stages(events)


def test_a_refusal_emits_no_progress_at_all() -> None:
    """A pre-LLM refusal short-circuits before context is even built."""
    from tests.insights._coach_stub import NoCallStub

    _, events = _run_with_events("do I have diabetes?", client=NoCallStub())
    assert events == []


def test_a_greeting_with_no_question_emits_no_progress() -> None:
    events: list[dict] = []
    result = coach.run_coach([], SENTINEL_USER_ID, SENTINEL_TZ, on_event=events.append)
    assert result.answered is False
    assert events == []


# ── the live draft (the owner's 2026-09-19 call) ──────────────────────────────
#
# These drive `coach_loop.ToolLoop` + `pipeline.drive` directly rather than through
# `coach.run_coach`, because a throttle test needs to inject a FAKE clock
# (`coach_loop.ToolLoop.clock`) and `run_coach` has no seam for one — it is exactly
# what `coach._loop` itself does internally, minus the refusal/greeting screen this
# suite does not need.


def _draft_events(events: list[dict]) -> list[dict]:
    return [e for e in events if e.get("event") == "draft"]


def _answer_cuts(full: str) -> tuple[int, int, int]:
    """Three character offsets into a `coach_answer` JSON answer: right after the
    opening closes, right after the first claim's `text` closes, and right after its
    `note_ids` array closes — the three points a streamed answer's draft prose changes
    shape (module docstring, `coach_draft`)."""
    after_opening = full.index('"claims"')
    after_text = full.index('"note_ids"')
    array_closes = full.index("]", after_text) + 1
    return after_opening, after_text, array_closes


def test_a_streamed_answer_emits_thinking_then_drafts_then_checking() -> None:
    full = VALID_ANSWER_JSON
    after_opening, after_text, array_closes = _answer_cuts(full)
    pieces = [full[:after_opening], full[:after_text], full[:array_closes]]
    stub = CoachStub([streamed(valid_turn(), pieces)])
    events: list[dict] = []
    loop = coach_loop.ToolLoop(
        client=stub,
        convo=[{"role": "user", "content": "how am I doing?"}],
        user_id=SENTINEL_USER_ID,
        tz=SENTINEL_TZ,
        on_event=events.append,
        clock=lambda: 0.0,  # every on_text call lands at the same instant
    )
    outcome = pipeline.drive(
        pipeline.Loop(
            next_turn=loop.next_turn,
            nudge=loop.nudge,
            label="coach",
            max_gathering_turns=coach.GATHERING_ROUNDS,
            context=loop.answer_context,
            on_event=events.append,
        )
    )
    assert outcome.text == VALID_REPLY
    assert _stages(events) == ["thinking", "checking"]
    drafts = _draft_events(events)
    # Two events survive a constant clock, not three: the SECOND piece lands 0.0s
    # after the first (< the 100ms throttle) and is coalesced; the round's FINAL
    # flush always ships regardless, carrying the fully-cited text — the wire
    # contract's own "always emit the final state" clause.
    assert len(drafts) == 2
    assert {d["round"] for d in drafts} == {1}
    assert drafts[-1]["text"] == VALID_REPLY
    # order: every draft sits strictly between `thinking` and `checking`.
    thinking_at = next(i for i, e in enumerate(events) if e.get("stage") == "thinking")
    checking_at = next(i for i, e in enumerate(events) if e.get("stage") == "checking")
    assert all(thinking_at < events.index(d) < checking_at for d in drafts)


def test_a_rewrite_starts_the_next_rounds_draft_from_empty_text() -> None:
    """A rejected candidate still streams its own draft; the accepted rewrite's draft
    is a fresh round, not a continuation of the rejected text."""
    full = VALID_ANSWER_JSON
    after_opening, _after_text, _array_closes = _answer_cuts(full)
    rejected = claim_turn("This is great", ["not_a_real_note"])
    accepted = streamed(valid_turn(), [full[:after_opening]])
    stub = CoachStub([rejected, accepted])
    events: list[dict] = []
    loop = coach_loop.ToolLoop(
        client=stub,
        convo=[{"role": "user", "content": "how am I doing?"}],
        user_id=SENTINEL_USER_ID,
        tz=SENTINEL_TZ,
        on_event=events.append,
        clock=lambda: 0.0,
    )
    outcome = pipeline.drive(
        pipeline.Loop(
            next_turn=loop.next_turn,
            nudge=loop.nudge,
            label="coach",
            max_gathering_turns=coach.GATHERING_ROUNDS,
            context=loop.answer_context,
            on_event=events.append,
        )
    )
    assert outcome.text == VALID_REPLY
    assert _stages(events) == ["thinking", "checking", "revising", "thinking", "checking"]
    round1_drafts = [d for d in _draft_events(events) if d["round"] == 1]
    round2_drafts = [d for d in _draft_events(events) if d["round"] == 2]
    assert round1_drafts and round2_drafts
    assert "This is great" not in round2_drafts[0]["text"]
    assert round2_drafts[0]["text"] == "Your recent numbers look steady."


# ── the observer cannot break a turn ──────────────────────────────────────────


def test_a_raising_observer_does_not_break_the_turn(caplog: pytest.LogCaptureFixture) -> None:
    def bad_observer(_event: dict) -> None:
        raise RuntimeError("a client watching this stream just vanished")

    with caplog.at_level(logging.ERROR):
        result = coach.run_coach(
            _ask("how am I doing?"),
            SENTINEL_USER_ID,
            SENTINEL_TZ,
            client=CoachStub([valid_turn()]),
            on_event=bad_observer,
        )
    assert result.validated is True
    assert any("progress observer raised" in r.message for r in caplog.records)


def test_on_event_none_is_byte_identical_to_a_silent_observer() -> None:
    """The default behaves exactly as it did before this parameter existed."""
    script = [claim_turn("This is great", ["not_a_real_note"]), valid_turn()]
    with_none = coach.run_coach(
        _ask("how am I doing?"), SENTINEL_USER_ID, SENTINEL_TZ, client=CoachStub(list(script))
    )
    with_noop = coach.run_coach(
        _ask("how am I doing?"),
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        client=CoachStub(list(script)),
        on_event=lambda _e: None,
    )
    assert with_none == with_noop
