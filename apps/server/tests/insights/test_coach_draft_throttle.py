"""The draft throttle emits CHANGE, not time: an unchanged prose is never re-sent.

Found by the lead's mutation sweep (2026-09-20): dropping the "same prose as last
time" guard survived every test. Harmless on the wire (the client replaces, so a
repeat draws nothing new) but it is a frame per repeated delta for nothing.
"""

from __future__ import annotations

from healthee.insights import coach_loop

_ANSWER = '{"coach_answer": {"opening": "You slept 6 h 20.", "claims": [], "asserts": []}}'


def test_the_same_prose_twice_emits_once_even_outside_the_throttle_window() -> None:
    clock = iter([0.0, 10.0, 20.0, 30.0, 40.0])
    emitted: list[str] = []
    throttle = coach_loop._DraftThrottle(emitted.append, lambda: next(clock))
    throttle.on_text(_ANSWER)
    throttle.on_text(_ANSWER)  # identical cumulative text, well past 100 ms
    throttle.flush(_ANSWER)
    assert emitted == ["You slept 6 h 20."]
