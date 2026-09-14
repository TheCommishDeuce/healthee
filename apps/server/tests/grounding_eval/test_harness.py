"""The harness's own machinery, offline: metering, classification, and its premises.

No network and no database — everything here is either arithmetic over fake responses or
a deterministic check the shipped code can answer for free. The most valuable test in the
file is the last one: the safety questions must be refused BEFORE any model call, which
is both the eval's floor and the reason those two questions cost nothing to run.
"""

from __future__ import annotations

import os
import re

import pytest
from tests.grounding_eval import questions as qs
from tests.grounding_eval import spend
from tests.grounding_eval.meter import MeteredClient
from tests.grounding_eval.records import (
    FALLBACK,
    GROUNDED,
    REFUSED,
    question_set_fingerprint,
)
from tests.grounding_eval.runner import _is_success, _outcome

from healthee.core.config import get_settings
from healthee.insights import morning
from healthee.insights.client import ChatResponse, Usage
from healthee.insights.coach import CoachResult
from healthee.insights.manifest import all_notes
from healthee.insights.refusals import classify_refusal


class _FakeInner:
    """An LLM that returns a scripted list of responses (usage included)."""

    def __init__(self, responses: list[ChatResponse]) -> None:
        self._responses = responses
        self.calls = 0

    def complete(  # noqa: ARG002
        self, messages: list[dict], *, tools=None, model=None, response_format=None
    ) -> ChatResponse:
        response = self._responses[min(self.calls, len(self._responses) - 1)]
        self.calls += 1
        return response


def _result(*, refused: bool = False, validated: bool = True) -> CoachResult:
    """A real surface result — the two flags ``_outcome`` reads, on the shipped type."""
    return CoachResult(reply="x", refused=refused, validated=validated)


# ── metering ─────────────────────────────────────────────────────────────────


def test_the_meter_totals_provider_counts_across_every_call_of_one_question() -> None:
    inner = _FakeInner(
        [
            ChatResponse(text="", tool_calls=[object()], usage=Usage(30_000, 100, 80)),
            ChatResponse(text="answer", usage=Usage(33_000, 400, 300)),
        ]
    )
    client = MeteredClient(inner)
    client.complete([])
    client.complete([])
    assert client.meter.llm_calls == 2
    assert client.meter.tool_rounds == 1  # only the turn that asked for tools
    assert client.meter.prompt_tokens == 63_000
    assert client.meter.completion_tokens == 500
    assert client.meter.reasoning_tokens == 380


def test_reset_separates_one_question_from_the_next() -> None:
    client = MeteredClient(_FakeInner([ChatResponse(text="x", usage=Usage(10, 2, 0))]))
    client.complete([])
    client.reset()
    client.complete([])
    assert client.meter.llm_calls == 1
    assert client.meter.prompt_tokens == 10


def test_a_call_the_provider_did_not_meter_is_counted_as_unknown_not_free() -> None:
    """Silently treating an unmetered call as zero would understate every cost figure."""
    client = MeteredClient(_FakeInner([ChatResponse(text="x")]))
    client.complete([])
    assert client.meter.unmetered_calls == 1
    assert client.meter.prompt_tokens == 0


def test_the_meter_sums_cached_prompt_tokens_across_every_call() -> None:
    """The other half of the bill — same treatment as prompt/completion/reasoning."""
    inner = _FakeInner(
        [
            ChatResponse(text="", usage=Usage(30_000, 100, 0, cached_prompt_tokens=25_000)),
            ChatResponse(text="answer", usage=Usage(33_000, 400, 0, cached_prompt_tokens=28_000)),
        ]
    )
    client = MeteredClient(inner)
    client.complete([])
    client.complete([])
    assert client.meter.cached_prompt_tokens == 53_000


def test_cached_prompt_tokens_reset_with_everything_else() -> None:
    client = MeteredClient(
        _FakeInner([ChatResponse(text="x", usage=Usage(10, 2, 0, cached_prompt_tokens=5))])
    )
    client.complete([])
    client.reset()
    assert client.meter.cached_prompt_tokens == 0


def test_a_response_with_no_usage_counts_zero_cached_not_unknown_as_free() -> None:
    """No usage at all is already ``unmetered_calls``; cached must not ALSO invent a number."""
    client = MeteredClient(_FakeInner([ChatResponse(text="x")]))
    client.complete([])
    assert client.meter.cached_prompt_tokens == 0
    assert client.meter.unmetered_calls == 1


def test_the_metered_client_returns_the_inner_response_untouched() -> None:
    """It observes; it must never become a second place that shapes an answer."""
    original = ChatResponse(text="verbatim", usage=Usage(1, 1, 0))
    client = MeteredClient(_FakeInner([original]))
    assert client.complete([]) is original


# ── classification ───────────────────────────────────────────────────────────


def test_a_validated_answer_is_the_only_thing_that_counts_as_shipped() -> None:
    assert _outcome(_result()) == GROUNDED
    assert _outcome(_result(validated=False)) == FALLBACK
    assert _outcome(_result(refused=True, validated=False)) == REFUSED


def test_success_is_measured_against_what_the_question_asked_for() -> None:
    answer_q = qs.QUESTIONS[0]
    refusal_q = next(q for q in qs.QUESTIONS if q.expect == qs.REFUSAL)
    assert _is_success(answer_q, GROUNDED) is True
    assert _is_success(answer_q, FALLBACK) is False
    assert _is_success(answer_q, REFUSED) is False  # a refused knowledge question is a failure
    assert _is_success(refusal_q, REFUSED) is True
    assert _is_success(refusal_q, GROUNDED) is False  # answering it is the worst outcome


# ── the question set's own premises ──────────────────────────────────────────


def test_the_safety_questions_are_refused_before_any_model_call() -> None:
    """The eval's floor, checkable for free: these two never reach the network."""
    safety = [q for q in qs.QUESTIONS if q.kind == qs.SAFETY]
    assert safety
    for question in safety:
        assert classify_refusal(question.text) is not None, question.id
        assert question.expect == qs.REFUSAL


def test_no_answer_expecting_question_trips_the_refusal_classifier() -> None:
    """A question that always refuses would silently score 0 forever and mean nothing."""
    for question in qs.QUESTIONS:
        if question.expect == qs.ANSWER:
            assert classify_refusal(question.text) is None, question.id


def test_the_question_set_spans_every_kind_it_claims_to() -> None:
    assert {q.kind for q in qs.QUESTIONS} >= {
        qs.KNOWLEDGE,
        qs.DATA,
        qs.COMPOUND,
        qs.OUT_OF_DOMAIN,
        qs.SAFETY,
    }


def test_question_ids_are_unique_because_pairing_keys_on_them() -> None:
    ids = [q.id for q in qs.QUESTIONS]
    assert len(ids) == len(set(ids))


def test_the_fingerprint_moves_when_a_prompt_is_edited() -> None:
    """Comparing two arms whose prompts differ is not a comparison; ``compare`` refuses."""
    original = question_set_fingerprint(qs.QUESTIONS)
    replacement = qs.EvalQuestion(id="x", kind="knowledge", surface="coach", text="?")
    edited = (*qs.QUESTIONS[:-1], replacement)
    assert original != question_set_fingerprint(edited)


def test_narrowing_by_kind_returns_only_that_kind() -> None:
    assert {q.kind for q in qs.by_kind({qs.DATA})} == {qs.DATA}
    assert qs.by_kind(None) == tuple(q for q in qs.QUESTIONS if q.kind in qs.DEFAULT_KINDS)


def test_an_opt_in_kind_costs_a_default_arm_nothing() -> None:
    """#129's absence questions (and #132's intent ones) must not raise the price — or
    move the fingerprint.

    Both halves matter and they are the same assertion from two sides: an unnamed run
    buys the same questions it bought yesterday, so the arms saved for #95/#99/#105 stay
    comparable (``compare`` refuses two arms whose fingerprints differ). Asking for the
    kind by name still buys it — an opt-in set nobody can select is a deleted set.
    """
    default = qs.by_kind(None)
    assert qs.ABSENCE not in {q.kind for q in default}
    assert qs.INTENT not in {q.kind for q in default}
    assert question_set_fingerprint(default) == question_set_fingerprint(
        tuple(q for q in qs.QUESTIONS if q.kind not in (qs.ABSENCE, qs.INTENT))
    )
    assert {q.kind for q in qs.by_kind({qs.ABSENCE})} == {qs.ABSENCE}
    assert len(qs.by_kind({qs.ABSENCE})) == 4
    assert {q.kind for q in qs.by_kind({qs.INTENT})} == {qs.INTENT}
    assert len(qs.by_kind({qs.INTENT})) == 12


def test_the_intent_questions_are_all_coach_answer_with_unique_ids() -> None:
    intent = qs.by_kind({qs.INTENT})
    assert all(q.surface == "coach" for q in intent)
    assert all(q.expect == qs.ANSWER for q in intent)
    ids = [q.id for q in intent]
    assert len(ids) == len(set(ids))
    assert all(qid.startswith("i_") for qid in ids)


def test_the_intent_questions_avoid_manifest_vocabulary() -> None:
    """The whole point of #132: plain-intent phrasing, none of retrieval's own words.

    Checked against the REAL manifest, not a hardcoded list, so a future edit to a
    question — or a new note/metric whose name happens to match one already in a
    question — cannot silently reintroduce the exact vocabulary these questions exist to
    withhold. Aliases are deliberately NOT checked here: "HRV" is itself a note alias
    (see ``i_hrv_worried``) and is also exactly what an owner types, which is the point.
    """
    notes = all_notes()
    names = {note.id for note in notes} | {m for note in notes for m in note.applies_to_metrics}
    for question in qs.by_kind({qs.INTENT}):
        lowered = question.text.lower()
        for name in names:
            assert not re.search(rf"\b{re.escape(name.lower())}\b", lowered), (
                question.id,
                name,
            )


def test_narrowing_by_id_returns_exactly_those_questions_in_the_sets_order() -> None:
    """Kind is too coarse to aim a paid run — the five shipped surfaces are one kind."""
    picked = qs.by_ids(["g_morning", "k_alcohol"])
    assert [q.id for q in picked] == ["k_alcohol", "g_morning"]


def test_an_unknown_question_id_raises_rather_than_running_a_smaller_set() -> None:
    """A typo must not spend money and then report a rate over a set nobody chose."""
    with pytest.raises(KeyError, match="g_mornning"):
        qs.by_ids(["g_morning", "g_mornning"])


def test_the_merged_morning_prompt_and_both_prompts_it_replaced_are_measurable() -> None:
    """#95 asks 'as reliably as the two separate ones' — all three must be in the set.

    And each must be the SHIPPED constant, not a copy: a paraphrase here would measure a
    prompt the product does not send, which is the drift the set exists to prevent.
    """
    texts = {q.id: q.text for q in qs.QUESTIONS}
    assert texts["g_morning"] == morning.MORNING_TASK
    assert texts["g_briefing"] == morning.BRIEFING_TASK
    assert texts["g_daily_action"] == morning.DAILY_ACTION_PROMPT


# ── whose credit a paid arm spends (#124) ──────────────────────────────────────


def test_an_eval_key_is_used_and_the_production_key_is_left_unspent(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """The whole point: with a key of its own, an arm cannot touch production's balance."""
    monkeypatch.setenv(spend.PROD_KEY_VAR, "prod-key-not-a-secret")
    monkeypatch.setenv(spend.EVAL_KEY_VAR, "eval-key-not-a-secret")
    monkeypatch.setattr(get_settings, "cache_clear", lambda: None)

    assert spend.select_api_key() == "eval"
    assert os.environ[spend.PROD_KEY_VAR] == "eval-key-not-a-secret"
    captured = capsys.readouterr()
    assert "eval-key-not-a-secret" not in captured.out + captured.err  # standards §Errors


def test_no_eval_key_still_runs_but_warns_that_it_is_spending_production(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """Not a gate. #102's lesson is 'nobody was told', not 'somebody ran an arm'."""
    monkeypatch.setenv(spend.PROD_KEY_VAR, "prod-key-not-a-secret")
    monkeypatch.delenv(spend.EVAL_KEY_VAR, raising=False)

    assert spend.select_api_key() == "production"
    warning = capsys.readouterr().err
    assert spend.EVAL_KEY_VAR in warning, "the warning must name the variable that fixes it"
    assert "PRODUCTION" in warning and "2026-08-01" in warning, "it must name the risk"
    assert "prod-key-not-a-secret" not in warning


def test_no_key_at_all_says_nothing_and_leaves_the_refusal_to_the_client(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """Two layers refusing the same missing key makes it ambiguous which one refused."""
    monkeypatch.delenv(spend.PROD_KEY_VAR, raising=False)
    monkeypatch.delenv(spend.EVAL_KEY_VAR, raising=False)

    assert spend.select_api_key() == "unset"
    assert capsys.readouterr().err == ""


def test_a_blank_eval_key_is_treated_as_unset_rather_than_as_a_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`EVAL_OPENROUTER_API_KEY=` in a .env would otherwise blank the production key too."""
    monkeypatch.setenv(spend.PROD_KEY_VAR, "prod-key-not-a-secret")
    monkeypatch.setenv(spend.EVAL_KEY_VAR, "   ")

    assert spend.select_api_key() == "production"
    assert os.environ[spend.PROD_KEY_VAR] == "prod-key-not-a-secret"
