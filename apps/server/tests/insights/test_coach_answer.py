"""#128 — an uncited interpretive claim is IMPOSSIBLE TO EXPRESS, not merely refused.

The old contract was a convention: write prose, remember to end each interpretive
sentence with ``[note_id]``, and the blocking validator will catch you if you forget.
Measured (INTELLIGENCE §9.5), a cheaper model forgot often enough to lose half its
knowledge answers — while matching the expensive one on every surface whose output was
already structured. Nothing wrong ever shipped; availability did.

So the guarantee this file holds is a STRUCTURAL one, and it has exactly three parts:

1. **A claim always ships with what grounds it.** ``render`` attaches the ids to every
   sentence of every claim; a claim with no ids ships carrying the honest escape in the
   same sentence. There is no third branch — which is what makes it mutation-testable.
2. **Interpretation cannot hide in the frame.** ``opening`` is free text, so an
   interpretive sentence there is redirected into ``claims`` rather than merely asked for
   a citation. Without this the shape would be advice, not structure.
3. **Nothing was weakened to buy it.** The rendered prose faces every existing answer
   gate; raw prose that skips the contract does not ship however well it is cited; and a
   declared grade stronger than the cited notes support is refused rather than believed.

**Mutation-verified, seven ways.** A guarantee nobody tried to break is a guarantee
nobody has measured, and five fictional mutations on this project the day before came
back "all pass" because they had silently not applied — so each of these was run with an
assertion that the substitution was on disk, and every one turned this file red:

  * an uncited claim ships bare (drop the escape from ``_cite_sentence``);
  * a cited claim ships with no ids at all (``_cite_sentence`` returns the sentence);
  * only the LAST sentence of a multi-sentence claim is cited;
  * the frame may carry a claim (``_opening_issues`` reads nothing);
  * a declared grade is believed rather than checked (``_grade_issue`` returns early);
  * raw prose is accepted (``pipeline._structure_gate`` reports nothing);
  * a malformed payload degrades back to free text instead of raising an issue.
"""

from __future__ import annotations

import json

import pytest
from tests.insights._coach_stub import (
    COACH_CLAIM,
    COACH_OPENING,
    VALID_ANSWER_JSON,
    VALID_REPLY,
    CoachStub,
    answer_payload,
    answer_turn,
    text_turn,
    valid_turn,
)
from tests.insights._ids import CONTESTED_ID, ESTABLISHED_ID, PROBABLE_ID

from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.insights import coach, coach_answer, coach_thread, prompts
from healthee.insights.calibration import HONEST_ESCAPE_RE
from healthee.insights.validator import validate


@pytest.fixture(autouse=True)
def _stub_context(monkeypatch: pytest.MonkeyPatch) -> None:
    """No DB and no network — this file is about the contract, not the SQL."""
    monkeypatch.setattr(
        coach,
        "_initial_messages",
        # Keeps the LAYOUT (a `system` turn, then the whole conversation) while
        # skipping the DB-backed context/evidence build. It used to return only the
        # last question, which discarded `history` — so no coach test exercised a
        # multi-turn context, and the thread-wide refusal screen could not have been
        # caught here however it behaved. The topic block rides along so a test can
        # assert what a topic does and does not put in front of the model.
        lambda history, q, user_id, tz, days, topic=None: [
            {"role": "system", "content": f"CONTEXT{coach_thread.topic_block(topic)}"},
            *history,
        ],
    )


def _run(*script) -> tuple[CoachStub, coach.CoachResult]:
    stub = CoachStub(list(script))
    result = coach.run_coach(
        [{"role": "user", "content": "how am I doing?"}],
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        client=stub,  # type: ignore[arg-type]
    )
    return stub, result


# ── 1 · a claim cannot reach the owner without its evidence ──────────────────


def test_the_renderer_attaches_the_ids_to_the_claim_it_was_given() -> None:
    """The pair the whole suite asserts against, pinned once so nobody types it twice."""
    answer, issues = coach_answer.parse(VALID_ANSWER_JSON)
    assert issues == ()
    assert answer is not None
    assert coach_answer.render(answer) == VALID_REPLY
    assert validate(VALID_REPLY).ok is True


def test_a_claim_with_no_citable_evidence_ships_marked_unsupported() -> None:
    """``note_ids: []`` is honest and allowed — and it is NOT silent.

    The escape lands INSIDE the claim's own sentence, because the honesty rules are
    enforced per sentence: a separate "no strong evidence" line would leave the claim
    itself uncited, which is the exact hole this shape closes. Mutating
    ``_cite_sentence`` to return the bare stem when there are no ids fails here.
    """
    payload = answer_payload(claims=[("Mid-afternoon caffeine is worth watching", [], "")])
    answer, issues = coach_answer.parse(json.dumps(payload))
    assert issues == ()
    assert answer is not None
    rendered = coach_answer.render(answer)
    assert coach_answer.NO_EVIDENCE in rendered
    assert HONEST_ESCAPE_RE.search(rendered), "the escape must be the validator's own"
    # One sentence, so the escape and the claim cannot be separated by a splitter.
    assert rendered.count(".") == 1
    assert validate(rendered).ok is True


def test_every_sentence_of_a_multi_sentence_claim_carries_the_citation() -> None:
    """A claim is rendered sentence by sentence, so the last one cannot carry the rest.

    A model writing two sentences into one claim is not a contract violation, but citing
    only the second would be the old failure in a smaller box.
    """
    two = "Your load has climbed for three weeks. Sustained ramps raise injury risk"
    payload = answer_payload(claims=[(two, [ESTABLISHED_ID], "Established")])
    answer, _ = coach_answer.parse(json.dumps(payload))
    assert answer is not None
    rendered = coach_answer.render(answer)
    assert rendered.count(f"[{ESTABLISHED_ID}]") == 2
    assert validate(rendered).ok is True


def test_the_citation_lands_before_the_terminator_not_after_it() -> None:
    """``truncation_issue`` reads the last line for a terminator — "…[id]" reads as cut off."""
    claim = ("Steady timing may help recovery.", [PROBABLE_ID], "Probable")
    payload = answer_payload(claims=[claim])
    answer, _ = coach_answer.parse(json.dumps(payload))
    assert answer is not None
    rendered = coach_answer.render(answer)
    assert rendered.endswith(f"[{PROBABLE_ID}].")
    assert validate(rendered).ok is True


def test_ids_the_model_wrote_inline_are_not_printed_twice() -> None:
    """Ids are a field now; an inline bracket is a habit, not a second citation."""
    payload = answer_payload(
        claims=[(f"Steady timing may help recovery [{PROBABLE_ID}].", [PROBABLE_ID], "Probable")]
    )
    answer, _ = coach_answer.parse(json.dumps(payload))
    assert answer is not None
    assert coach_answer.render(answer).count(PROBABLE_ID) == 1


def test_a_personal_finding_tag_survives_rendering() -> None:
    """``[personal_finding:…]`` is the one citation the model still writes inline (§4)."""
    text = "When your MVPA rose 20%, your HRV followed [personal_finding:mvpa_hrv]"
    payload = answer_payload(claims=[(text, [ESTABLISHED_ID], "Established")])
    answer, _ = coach_answer.parse(json.dumps(payload))
    assert answer is not None
    rendered = coach_answer.render(answer)
    assert "[personal_finding:mvpa_hrv]" in rendered
    assert f"[{ESTABLISHED_ID}]" in rendered


# ── 2 · interpretation cannot hide in the frame ──────────────────────────────


def test_an_interpretive_opening_is_redirected_into_claims() -> None:
    """Without this the shape is advisory: everything could go in ``opening`` uncited.

    Emptying ``_opening_issues`` fails this test — and only this one, which is why it is
    the mutation that proves the frame check is load-bearing rather than decorative.
    """
    payload = answer_payload(
        opening="Your recovery is low because your sleep debt has been building.",
        claims=[(COACH_CLAIM, [ESTABLISHED_ID], "Established")],
    )
    _, issues = coach_answer.parse(json.dumps(payload))
    assert any("Interpretive sentence in the opening" in issue for issue in issues)


def test_a_descriptive_opening_that_quotes_real_numbers_is_legal() -> None:
    """The check is the validator's own, exemptions included — reporting is not claiming.

    If it were stricter than that, the shape would cost availability at the exact moment
    the coach is doing the honest thing: stating what was measured.
    """
    for opening in (
        "Your RHR averaged 54 bpm this week, one below your 30-day median.",
        "Your sleep last night was 6h12m across four sessions.",
        COACH_OPENING,
    ):
        _, issues = coach_answer.parse(json.dumps(answer_payload(opening=opening)))
        assert issues == (), f"a descriptive opening was refused: {opening!r} → {issues}"


def test_an_interpretive_opening_does_not_ship_even_when_it_is_cited() -> None:
    """A citation does not buy the frame the right to make claims — the channel does."""
    payload = answer_payload(
        opening=f"Your recovery is low because of sleep debt [{ESTABLISHED_ID}].",
        claims=[(COACH_CLAIM, [ESTABLISHED_ID], "Established")],
    )
    _, result = _run(text_turn(json.dumps(payload)), text_turn(json.dumps(payload)))
    assert result.reply == prompts.FALLBACK
    assert result.validated is False


# ── 3 · nothing was weakened to buy it ───────────────────────────────────────


def test_raw_prose_never_ships_however_well_it_is_cited() -> None:
    """The contract is not advice. Prose that would have validated yesterday falls back.

    This is the test neutering ``pipeline._structure_gate`` breaks: the prose below is
    clean by every OTHER gate, so if the structure gate stops raising its issue the reply
    ships and the guarantee is gone.
    """
    prose = f"Your numbers look steady. Consistent activity may support fitness [{ESTABLISHED_ID}]."
    assert validate(prose).ok is True, "the fixture must be clean by every other gate"
    stub, result = _run(text_turn(prose), text_turn(prose), text_turn(prose))
    assert result.reply == prompts.FALLBACK
    assert result.validated is False
    assert stub.calls == 3  # the attempt plus its two nudged rewrites


def test_a_fabricated_id_in_the_note_ids_field_is_still_blocked() -> None:
    """The ids moved into a field; the manifest check did not move with them.

    Rendering puts them back into the text, so ``validator``'s fabricated-id rule sees
    exactly what it always saw. Nothing here re-implements it — that would be a second
    definition of "a real note".
    """
    claim = ("Your recovery suggests overtraining", ["not_a_real_note"], "")
    payload = answer_payload(claims=[claim])
    _, result = _run(
        text_turn(json.dumps(payload)),
        text_turn(json.dumps(payload)),
        text_turn(json.dumps(payload)),
    )
    assert result.reply == prompts.FALLBACK
    assert "not_a_real_note" not in result.reply


def test_a_hard_output_guardrail_still_blocks_a_claim_without_a_retry() -> None:
    """A forbidden output is a floor, and the floor is under the renderer too."""
    forbidden = "At this activity level your life expectancy is around 79"
    payload = answer_payload(claims=[(forbidden, [ESTABLISHED_ID], "Established")])
    stub, result = _run(text_turn(json.dumps(payload)))
    assert result.refused is True
    assert stub.calls == 1, "a blocked answer is never nudged"


def test_an_overclaimed_grade_is_refused_rather_than_believed() -> None:
    """INTELLIGENCE §5.6's hole, closed on the coach: a declared grade is CHECKED.

    Declaring Established over a Contested note is the shape that let a rec ship a debated
    claim as settled. The issue names both grades, because a nudge that does not say what
    the right answer is buys a second identical attempt.
    """
    claim = ("Cold exposure may aid recovery", [CONTESTED_ID], "Established")
    payload = answer_payload(claims=[claim])
    _, issues = coach_answer.parse(json.dumps(payload))
    assert any("declares Established" in issue and "Contested" in issue for issue in issues)


def test_declaring_a_weaker_grade_than_the_notes_require_is_allowed() -> None:
    """Under-claiming costs a hedge nobody owed. Spending a retry to make an answer less
    careful is not something this product should do."""
    payload = answer_payload(
        claims=[("Consistent activity may support fitness", [ESTABLISHED_ID], "Probable")]
    )
    _, issues = coach_answer.parse(json.dumps(payload))
    assert issues == ()


def test_the_grade_calibration_rule_still_runs_on_the_rendered_text() -> None:
    """The declared grade is an ADDITIONAL check, never a replacement for the wording rule.

    A correctly declared Probable claim written with flat certainty must still fail — if it
    did not, the field would have bought the model an exemption from the calibration gate.
    """
    flat = "Afternoon caffeine cuts your deep sleep because it blocks adenosine"
    payload = answer_payload(claims=[(flat, [PROBABLE_ID], "Probable")])
    _, result = _run(
        text_turn(json.dumps(payload)),
        text_turn(json.dumps(payload)),
        text_turn(json.dumps(payload)),
    )
    assert result.reply == prompts.FALLBACK


# ── the payload the model actually sends ─────────────────────────────────────


def test_a_fenced_or_prefaced_payload_is_still_read() -> None:
    """A code fence is a formatting slip, not an ungrounded answer.

    JSON mode cannot be requested on a round that also offers tools, so the shape usually
    arrives by instruction alone; refusing a fence would spend a paid retry proving the
    model can count backticks.
    """
    for raw in (
        f"```json\n{VALID_ANSWER_JSON}\n```",
        f"Here you go:\n{VALID_ANSWER_JSON}",
        f"```\n{VALID_ANSWER_JSON}\n```\nHope that helps!",
    ):
        answer, issues = coach_answer.parse(raw)
        assert issues == (), raw[:40]
        assert answer is not None
        assert coach_answer.render(answer) == VALID_REPLY


@pytest.mark.parametrize(
    "raw",
    [
        "I could not answer that.",
        '{"answer": "something"}',
        '{"coach_answer": {"claims": "not a list"}}',
        '{"coach_answer": {"opening": "", "claims": []}}',
        '{"coach_answer": {"claims": [{"note_ids": ["x"]}]}}',
        "{",
    ],
)
def test_a_payload_outside_the_contract_raises_an_issue(raw: str) -> None:
    """Every malformed shape is an ISSUE, never a quiet degradation back to prose."""
    _, issues = coach_answer.parse(raw)
    assert issues, f"{raw!r} produced no structural issue"


def test_an_unparseable_answer_still_faces_the_output_guardrails() -> None:
    """It cannot ship — but it is handed on, so the floor sees whatever was written."""
    forbidden = "At this activity level your life expectancy is around 79."
    _, result = _run(text_turn(forbidden))
    assert result.refused is True


# ── the wiring ───────────────────────────────────────────────────────────────


def test_the_contract_is_in_the_prompt_and_the_pinned_persona_is_untouched() -> None:
    """The shape is APPENDED like the context and evidence blocks; the doc stays the doc."""
    from healthee.insights.coach_prompt import COACH_SYSTEM_PROMPT

    assert coach_answer.ROOT_KEY not in COACH_SYSTEM_PROMPT
    assert coach_answer.ROOT_KEY in coach_answer.ANSWER_SHAPE
    assert coach_answer.NO_EVIDENCE in coach_answer.ANSWER_SHAPE


def test_json_mode_is_requested_only_when_no_tools_are_offered() -> None:
    """The two are not reliably combinable, and a round that answers offers no tools."""
    seen: list[tuple[bool, object]] = []

    class _Spy:
        calls = 0

        def complete(  # noqa: ANN001, ARG002
            self,
            messages,
            *,
            tools=None,
            model=None,
            response_format=None,
            reasoning=None,
            on_text=None,
        ):
            seen.append((tools is not None, response_format))
            self.calls += 1
            return valid_turn()

    coach.run_coach(
        [{"role": "user", "content": "how am I doing?"}],
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        client=_Spy(),  # type: ignore[arg-type]
    )
    assert seen == [(True, None)]


def test_the_nudge_carries_the_payload_back_not_the_rendered_prose() -> None:
    """The model is being asked to correct JSON; showing it prose invites prose."""
    bad = json.dumps(answer_payload(claims=[("It suggests overtraining", ["not_a_real_note"], "")]))
    stub, _ = _run(text_turn(bad), valid_turn())
    echoed = [m for m in stub.messages_seen[-1] if m.get("role") == "assistant"]
    assert echoed and echoed[-1]["content"] == bad
    nudge = [m for m in stub.messages_seen[-1] if m.get("role") == "user"][-1]["content"]
    assert coach_answer.ROOT_KEY in nudge


def test_a_compliant_answer_ships_with_its_grounding_metadata() -> None:
    """End to end: the reply is the rendered prose and the citations came out of it."""
    _, result = _run(answer_turn(COACH_OPENING, [(COACH_CLAIM, [ESTABLISHED_ID], "Established")]))
    assert result.reply == VALID_REPLY
    assert result.validated is True
    assert result.citations == [ESTABLISHED_ID]
    assert result.grade_floor == "Established"
