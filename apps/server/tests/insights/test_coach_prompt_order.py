"""The coach system turn is laid out for the provider's prompt cache.

A prompt cache matches a byte-identical PREFIX. The parts that repeat across questions —
the coach prompt, the evidence notes, the answer contract — therefore come first, and the
parts that change per owner and per day — their data, the turn's subject — come last.
Measured before this order: 44% coach cache hit with the owner's data ahead of a ~40k-token
evidence block. These tests pin the order without a model or a database.
"""

from __future__ import annotations

from uuid import uuid4

import pytest

from healthee.insights import coach, coach_answer
from healthee.insights.coach_prompt import COACH_SYSTEM_PROMPT


@pytest.fixture
def _stubbed_blocks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(coach, "build_coach_context", lambda *_a, **_k: "OWNER-DATA-BLOCK")
    monkeypatch.setattr(coach, "coach_evidence", lambda *_a, **_k: "# EVIDENCE NOTES\nNOTE-BLOCK")


def _system(topic: str | None = None) -> str:
    messages = coach._initial_messages([], "how did I sleep?", uuid4(), "UTC", 60, topic=topic)
    assert messages[0]["role"] == "system"
    return messages[0]["content"]


def test_stable_parts_precede_the_owners_data(_stubbed_blocks: None) -> None:
    system = _system()
    i_prompt = system.index(COACH_SYSTEM_PROMPT)
    i_evidence = system.index("# EVIDENCE NOTES")
    i_shape = system.index(coach_answer.ANSWER_SHAPE)
    i_data = system.index("OWNER-DATA-BLOCK")
    assert i_prompt < i_evidence < i_shape < i_data


def test_the_turns_subject_is_last_of_all(_stubbed_blocks: None) -> None:
    system = _system(topic="zq-subject-marker")
    assert system.index("OWNER-DATA-BLOCK") < system.index("zq-subject-marker")


def test_the_owners_data_keeps_its_heading(_stubbed_blocks: None) -> None:
    """The model still needs to know which block is the owner's data; moving it must not
    strip the heading that names it."""
    system = _system()
    assert "# THE USER'S DATA (CONTEXT)" in system
    assert system.index("# THE USER'S DATA (CONTEXT)") < system.index("OWNER-DATA-BLOCK")
