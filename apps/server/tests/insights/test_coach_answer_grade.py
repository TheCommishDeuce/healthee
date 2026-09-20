"""The declared grade is REPLACED by the provable one — split out of
``test_coach_answer.py`` at the 400-line gate.

The refusal these tests used to pin ("declares Established but its weakest cited note
is Probable") was measured as the commonest reason a coach turn was rewritten; the
server always knew the answer, so it now takes it and moves on. The wording gate that
judges the sentence's hedge against the same note grades is the validator's, and is
tested there.
"""

from __future__ import annotations

import json

from tests.insights._coach_stub import answer_payload
from tests.insights._ids import CONTESTED_ID

from healthee.insights import coach_answer


def test_an_overclaimed_grade_is_replaced_by_the_provable_one_not_believed() -> None:
    """INTELLIGENCE section 5.6's hole, closed on the coach without a rewrite: a declared
    grade is never believed — the claim carries the grade its cited notes prove — and it
    is no longer REFUSED either, because that refusal was the commonest reason a turn was
    rewritten (11 of 14 measured fallbacks) for a number the server already had."""
    claim = ("Cold exposure may aid recovery", [CONTESTED_ID], "Established")
    payload = answer_payload(claims=[claim])
    answer, issues = coach_answer.parse(json.dumps(payload))
    assert not [issue for issue in issues if "declares" in issue]
    assert answer is not None
    assert answer.claims[0].grade == "Contested"


def test_an_unknown_declared_grade_is_replaced_too() -> None:
    payload = answer_payload(claims=[("Cold exposure may aid recovery", [CONTESTED_ID], "Solid")])
    answer, issues = coach_answer.parse(json.dumps(payload))
    assert not [issue for issue in issues if "grade" in issue.lower()]
    assert answer is not None
    assert answer.claims[0].grade == "Contested"
