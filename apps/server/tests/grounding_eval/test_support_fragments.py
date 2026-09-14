"""``support.py`` continued: heading-only passage exclusion, multi-fragment claims, and
the opt-in real-model smoke test — split out of ``test_support.py`` to stay under the
400-line file gate. Shares that file's ``FakeNLI``/``_fake_corpus``/``_claim`` fixtures
rather than redefining them a second, possibly divergent, way.
"""

from __future__ import annotations

import os

import pytest
from tests.grounding_eval import support
from tests.grounding_eval.test_support import (
    _EMPTY_ID,
    _HEADING_ID,
    _KNOWN_ID,
    _SECOND_ID,
    _THREE_ID,
    FakeNLI,
    _claim,
    _fake_passages,
)

from healthee.insights.passages import Passage


@pytest.fixture
def _fake_corpus(monkeypatch: pytest.MonkeyPatch) -> None:
    """The same tiny fixed corpus as ``test_support._fake_corpus`` — reconstructed
    (rather than imported as a fixture object, which trips ruff's redefinition check
    on the parameter name every test below needs) from that file's shared constants
    and ``_fake_passages``, so there is still only ONE corpus definition."""
    monkeypatch.setattr(
        support.manifest,
        "note_ids",
        lambda: {_KNOWN_ID, _EMPTY_ID, _THREE_ID, _SECOND_ID, _HEADING_ID},
    )
    monkeypatch.setattr(support.passages_mod, "passages", _fake_passages)


# ── Heading-only passages are never premises ─────────────────────────────────


def test_heading_only_passages_are_excluded_even_when_they_would_win(_fake_corpus: None) -> None:
    """`heading_only_note` has three passages: an ATX H1 title, a bold-label
    sub-heading, and one real prose passage. Both structural passages are rigged to
    look like the STRONGEST match — if either were used as a premise the claim would
    "win" on the wrong evidence. The real passage must win instead, at its own
    (lower) score, because the other two are never candidates at all."""
    fake = FakeNLI(
        rules={
            ("Grip strength research", "Widgets"): (0.0, 0.99, 0.01),  # the H1 title — must lose
            ("Key takeaway", "Widgets"): (0.0, 0.97, 0.03),  # the bold label — must lose
            ("reliably enhance grip strength over eight weeks", "Widgets"): (0.05, 0.6, 0.35),
        }
    )
    score = _claim(fake, f"Widgets may improve grip strength [{_HEADING_ID}].")
    detail = score.details[0]
    assert detail.best_ref == f"{_HEADING_ID}#p2"
    assert detail.entailment == pytest.approx(0.6)
    assert detail.supported is True


def test_a_note_of_only_heading_shaped_passages_is_unscorable_not_unsupported(
    _fake_corpus: None,
) -> None:
    """Citing ONLY the two structural passages (never the real one) leaves nothing to
    entail from — this is UNSCORABLE (nothing was ever tested), a different state from
    an "unsupported" claim the model actually rejected. Not a crash, not a silent skip
    either: `SupportScore.unscorable` counts it."""

    def fake_passages(note_id: str) -> tuple[Passage, ...]:
        if note_id == "titles_only":
            return (
                Passage("titles_only", 0, "", "# Some Note Title"),
                Passage("titles_only", 1, "Evidence", "**A group label**"),
            )
        return ()

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(support.manifest, "note_ids", lambda: {"titles_only"})
        mp.setattr(support.passages_mod, "passages", fake_passages)
        score = _claim(FakeNLI(), "Widgets may improve grip strength [titles_only].")
    detail = score.details[0]
    assert detail.best_ref is None
    assert detail.scorable is False
    assert detail.supported is False
    assert score.unscorable == 1


# ── Multi-fragment claims: the plumbing decomposition feeds into scoring ─────


def test_a_multi_fragment_claim_reports_the_actual_winning_fragment(_fake_corpus: None) -> None:
    """The sentence splits (on " and ") into two fragments; only the SECOND one
    matches any passage. `best_fragment` must name that fragment text, not the whole
    original sentence — the field this whole rewrite exists to make trustworthy."""
    sentence = (
        "Widgets are popular in many gyms and independent trials show widgets "
        "reliably improve grip strength [known_note]."
    )
    fake = FakeNLI(
        rules={
            ("reliably improve grip strength", "reliably improve grip strength"): (0.02, 0.88, 0.10)
        }
    )
    score = _claim(fake, sentence)
    detail = score.details[0]
    assert len(detail.fragments) == 2
    assert detail.best_fragment is not None
    assert detail.best_fragment != sentence
    assert "independent trials show widgets reliably improve grip strength" in detail.best_fragment
    assert detail.entailment == pytest.approx(0.88)
    assert detail.supported is True


def test_one_predict_call_covers_every_fragment_of_a_multi_fragment_claim(
    _fake_corpus: None,
) -> None:
    sentence = (
        "Widgets are popular in many gyms and independent trials show widgets "
        "reliably improve grip strength [known_note]."
    )
    fake = FakeNLI()
    score = _claim(fake, sentence)
    assert score.claims == 1
    assert fake.calls == 1
    # 2 fragments x 2 passages of `known_note` = 4 pairs, in the one batch.
    assert len(fake.batches[0]) == 4


def test_the_winning_fragments_own_contradiction_travels_even_across_a_shared_ref(
    _fake_corpus: None,
) -> None:
    """(review S7) Both fragments of this claim are tested against the SAME passage
    (`known_note#p0`): the LOSING fragment ("popular in many gyms") is rigged with a
    HIGH contradiction and low entailment, the WINNING one ("independent trials...")
    with a LOW contradiction and high entailment. A mutation that folded the two
    contradictions together (e.g. `max(contradiction, current[2])`) would report the
    losing fragment's 0.9 here instead of the winner's own 0.02 — this is exactly the
    single-ref case the old test suite never constructed."""
    sentence = (
        "Widgets are popular in many gyms and independent trials show widgets "
        "reliably improve grip strength [known_note]."
    )
    fake = FakeNLI(
        rules={
            ("Widgets reliably improve grip strength.", "popular in many gyms"): (0.9, 0.05, 0.05),
            ("Widgets reliably improve grip strength.", "independent trials"): (0.02, 0.93, 0.05),
        }
    )
    score = _claim(fake, sentence)
    detail = score.details[0]
    assert detail.best_ref == f"{_KNOWN_ID}#p0"
    assert detail.entailment == pytest.approx(0.93)
    assert detail.contradiction == pytest.approx(0.02)


def test_owner_data_wrapped_claim_still_gets_a_fragment_to_test(_fake_corpus: None) -> None:
    """(review fix a) The exact false negative the review caught: a sentence that is
    both the owner's own number AND a checkable note-grounded claim in one breath, with
    nothing to split on. `quotes_own_measurement` correctly flags the WHOLE sentence,
    but the fallback is now unconditional — this must still be tested, and here it is
    rigged to be genuinely SUPPORTED, proving it reaches the model at all."""
    sentence = (
        "Your sleep regularity index (SRI) is 74.0, which meets the established "
        "threshold of 70 [known_note]."
    )
    fake = FakeNLI(rules={("improve grip strength", "sleep regularity index"): (0.02, 0.9, 0.08)})
    score = _claim(fake, sentence)
    detail = score.details[0]
    assert detail.fragments == (sentence,)
    assert detail.scorable is True
    assert detail.supported is True
    assert score.unscorable == 0


# ── Opt-in real-model smoke test ─────────────────────────────────────────────


def test_real_model_smoke() -> None:
    """Scores an obviously-entailed pair and an obviously-unrelated pair against a
    real note passage, on the real ``cross-encoder/nli-deberta-v3-base`` checkpoint.

    Opt-in: skipped unless ``HEALTHEE_SUPPORT_MODEL_TESTS=1`` AND
    ``sentence_transformers`` actually imports (the ``eval`` dependency group).
    """
    if os.environ.get("HEALTHEE_SUPPORT_MODEL_TESTS") != "1":
        pytest.skip("opt-in: set HEALTHEE_SUPPORT_MODEL_TESTS=1 to run against the real model")
    pytest.importorskip("sentence_transformers")
    from healthee.insights import passages as real_passages

    nli = support._load_nli()
    premise = next(
        p.text
        for p in real_passages.passages("aerobic_decoupling")
        if "Cardiovascular drift is real and well-characterised" in p.text
    )
    entailed = (
        "Cardiovascular drift is a real, well-documented phenomenon during prolonged exercise."
    )
    unrelated = "Bananas are a good source of potassium for marathon runners."
    (_, e_entailed, _), (_, e_unrelated, _) = nli.predict(
        [(premise, entailed), (premise, unrelated)]
    )
    assert e_entailed > 0.9
    assert e_unrelated < 0.1
