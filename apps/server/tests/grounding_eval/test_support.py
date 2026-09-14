"""``tests/grounding_eval/support.py`` — the entailment scorer, against a fake NLI.

Every test here injects a fake :class:`support.NLI` and monkeypatches
``manifest.note_ids`` / ``passages.passages``, so nothing downloads a model, hits the
network, or touches the real corpus — this file must stay fast enough to run in the
normal suite. The one test that exercises the REAL model is opt-in (see the bottom of
this file) and is not part of that contract.
"""

from __future__ import annotations

import os
from collections.abc import Sequence
from dataclasses import dataclass, field

import pytest
from tests.grounding_eval import support

from healthee.insights.passages import Passage

_KNOWN_ID = "known_note"  # in the (fake) manifest, carries two passages
_EMPTY_ID = "empty_note"  # in the (fake) manifest, carries zero passages
_UNKNOWN_ID = "unknown_note_not_in_manifest"  # never in the (fake) manifest
_THREE_ID = "known_note_three"  # carries three passages; the winner sits at index 2
_SECOND_ID = "second_known_note"  # a second cited note, carrying the true winner


@dataclass
class FakeNLI:
    """A dict-driven stand-in for the real cross-encoder.

    ``rules`` maps ``(premise_substring, hypothesis_substring)`` to the
    ``(contradiction, entailment, neutral)`` triple to return for any pair matching
    both substrings; an unmatched pair defaults to neutral (0, 0, 1), same as an NLI
    model asked about two things that have nothing to do with each other.
    """

    rules: dict[tuple[str, str], tuple[float, float, float]] = field(default_factory=dict)
    calls: int = 0
    batches: list[list[tuple[str, str]]] = field(default_factory=list)

    def predict(self, pairs: Sequence[tuple[str, str]]) -> Sequence[tuple[float, float, float]]:
        self.calls += 1
        self.batches.append(list(pairs))
        return [self._one(premise, hypothesis) for premise, hypothesis in pairs]

    def _one(self, premise: str, hypothesis: str) -> tuple[float, float, float]:
        for (p_sub, h_sub), probs in self.rules.items():
            if p_sub in premise and h_sub in hypothesis:
                return probs
        return (0.0, 0.0, 1.0)


@pytest.fixture
def _fake_corpus(monkeypatch: pytest.MonkeyPatch) -> None:
    """A tiny, fully controlled manifest + passage set — no real corpus involved.

    NOT autouse: the one real-model test at the bottom of this file must see the
    REAL manifest/passages, and this patches the actual `healthee.insights.passages`
    module object (`support.passages_mod` is the same module, not a copy), so an
    autouse fixture here would corrupt that test's own corpus lookups too.
    """
    monkeypatch.setattr(
        support.manifest,
        "note_ids",
        lambda: {_KNOWN_ID, _EMPTY_ID, _THREE_ID, _SECOND_ID},
    )

    def fake_passages(note_id: str) -> tuple[Passage, ...]:
        if note_id == _KNOWN_ID:
            return (
                Passage(_KNOWN_ID, 0, "Evidence", "Widgets reliably improve grip strength."),
                Passage(_KNOWN_ID, 1, "Evidence", "Widgets have no effect on grip strength."),
            )
        if note_id == _THREE_ID:
            return (
                Passage(
                    _THREE_ID, 0, "Evidence", "Widgets are ineffective and provide no benefit."
                ),
                Passage(
                    _THREE_ID,
                    1,
                    "Evidence",
                    "This passage is unrelated filler about something else.",
                ),
                Passage(
                    _THREE_ID,
                    2,
                    "Evidence",
                    "Widgets have been proven to reliably enhance grip strength.",
                ),
            )
        if note_id == _SECOND_ID:
            return (
                Passage(
                    _SECOND_ID, 0, "Evidence", "Trials confirm the device enhances grip strength."
                ),
            )
        return ()

    monkeypatch.setattr(support.passages_mod, "passages", fake_passages)


def _claim(fake: FakeNLI, text: str, *, threshold: float = 0.5) -> support.SupportScore:
    return support.score_answer(text, threshold=threshold, nli=fake)


# ── Claim selection ──────────────────────────────────────────────────────────


def test_uncited_claim_counts_as_a_claim_but_not_a_cited_claim(_fake_corpus: None) -> None:
    score = _claim(FakeNLI(), "This may be true but cites no note at all.")
    assert score.claims == 1
    assert score.cited_claims == 0
    assert score.supported == 0
    assert score.details[0].cited == ()
    assert score.details[0].best_ref is None


def test_citation_to_an_unrecognised_id_is_ignored(_fake_corpus: None) -> None:
    score = _claim(FakeNLI(), f"Widgets may help grip strength [{_UNKNOWN_ID}].")
    assert score.claims == 1
    assert score.cited_claims == 0  # the citation exists in the TEXT but not the manifest
    assert score.details[0].cited == ()


def test_heading_units_never_count_as_claims(_fake_corpus: None) -> None:
    """The bold-only heading line contains "may" and "show" — both interpretive
    markers — and must still be skipped entirely; only the real sentence counts."""
    text = "**This may show something interesting**\n\nWidgets may help grip strength [known_note]."
    score = _claim(FakeNLI(), text)
    assert score.claims == 1
    assert score.details[0].sentence.startswith("Widgets may help")


def test_empty_text_is_a_valid_honest_zero_not_an_error(_fake_corpus: None) -> None:
    score = _claim(FakeNLI(), "")
    assert score == support.SupportScore(
        claims=0, cited_claims=0, supported=0, threshold=0.5, details=()
    )


# ── Entailment scoring ───────────────────────────────────────────────────────


def test_cited_claim_with_an_entailing_passage_is_supported(_fake_corpus: None) -> None:
    fake = FakeNLI(rules={("improve grip strength", "Widgets"): (0.02, 0.9, 0.08)})
    score = _claim(fake, "Widgets may improve grip strength [known_note].")
    assert score.claims == 1
    assert score.cited_claims == 1
    assert score.supported == 1
    detail = score.details[0]
    assert detail.best_ref == f"{_KNOWN_ID}#p0"
    assert detail.entailment == pytest.approx(0.9)
    assert detail.supported is True


def test_max_entailment_wins_and_its_own_contradiction_travels_with_it(_fake_corpus: None) -> None:
    """p1 ("no effect") is the more CONTRADICTORY passage but the WEAKER entailment;
    p0 must win on entailment, and the reported contradiction must be p0's own value
    (0.02) rather than p1's much larger one (0.8) — a mutation that maximised
    contradiction independently would report 0.8 here instead."""
    fake = FakeNLI(
        rules={
            ("reliably improve grip strength", "Widgets"): (0.02, 0.9, 0.08),
            ("no effect on grip strength", "Widgets"): (0.8, 0.05, 0.15),
        }
    )
    score = _claim(fake, "Widgets may improve grip strength [known_note].")
    detail = score.details[0]
    assert detail.best_ref == f"{_KNOWN_ID}#p0"
    assert detail.entailment == pytest.approx(0.9)
    assert detail.contradiction == pytest.approx(0.02)
    assert detail.supported is True


def test_max_entailment_can_win_from_a_non_zero_index(_fake_corpus: None) -> None:
    """S1 (mutation review): the winning passage is p2, not p0 — `known_note_three`'s
    p0 is a high-contradiction decoy and p1 is neutral filler. A mutation that
    replaced the argmax search with a hardcoded `best = 0` passed every prior test
    here because each one's entailing passage happened to sit at index 0; this one
    does not, so that mutation now reports p0's (wrong) numbers instead of p2's."""
    fake = FakeNLI(
        rules={
            ("ineffective and provide no benefit", "Widgets"): (0.9, 0.02, 0.08),
            ("unrelated filler", "Widgets"): (0.0, 0.0, 1.0),
            ("proven to reliably enhance grip strength", "Widgets"): (0.01, 0.95, 0.04),
        }
    )
    score = _claim(fake, f"Widgets may improve grip strength [{_THREE_ID}].")
    detail = score.details[0]
    assert detail.best_ref == f"{_THREE_ID}#p2"
    assert detail.entailment == pytest.approx(0.95)
    assert detail.contradiction == pytest.approx(0.01)
    assert detail.supported is True


def test_max_entailment_can_win_in_a_later_cited_note(_fake_corpus: None) -> None:
    """Two notes cited on one claim; the true winner is the SECOND note's only
    passage, not anything in the first — proves the max search runs over every
    cited note's passages together, not just the first note's."""
    fake = FakeNLI(
        rules={
            ("ineffective and provide no benefit", "Gadgets"): (0.9, 0.02, 0.08),
            ("unrelated filler", "Gadgets"): (0.0, 0.0, 1.0),
            ("proven to reliably enhance grip strength", "Gadgets"): (0.05, 0.2, 0.75),
            ("Trials confirm the device enhances grip strength", "Gadgets"): (0.0, 0.97, 0.03),
        }
    )
    score = _claim(fake, f"Gadgets may improve grip strength [{_THREE_ID}, {_SECOND_ID}].")
    detail = score.details[0]
    assert detail.best_ref == f"{_SECOND_ID}#p0"
    assert detail.entailment == pytest.approx(0.97)


def test_threshold_boundary_is_inclusive(_fake_corpus: None) -> None:
    at_threshold = FakeNLI(rules={("improve grip strength", "Widgets"): (0.0, 0.5, 0.5)})
    just_under = FakeNLI(rules={("improve grip strength", "Widgets"): (0.0, 0.4999, 0.5001)})
    text = "Widgets may improve grip strength [known_note]."
    assert _claim(at_threshold, text, threshold=0.5).details[0].supported is True
    assert _claim(just_under, text, threshold=0.5).details[0].supported is False


def test_cited_note_with_zero_passages_is_unsupported_not_skipped(_fake_corpus: None) -> None:
    """`empty_note` is a real id (in the fake manifest) with no passages to entail
    from — the honest answer is unsupported, never a silently dropped claim."""
    score = _claim(FakeNLI(), f"Widgets may help grip strength [{_EMPTY_ID}].")
    assert score.claims == 1
    assert score.cited_claims == 1  # the citation is real; there is just nothing behind it
    assert score.supported == 0
    assert score.details[0].best_ref is None
    assert score.details[0].entailment == 0.0


def test_one_predict_call_covers_every_claim_in_the_answer(_fake_corpus: None) -> None:
    """Two claims, each citing the two-passage note, must still be ONE `predict`
    call over all four pairs — never one call per claim or per passage."""
    fake = FakeNLI()
    text = (
        "Widgets may improve grip strength [known_note]. "
        "Gadgets likely improve grip strength too [known_note]."
    )
    score = _claim(fake, text)
    assert score.claims == 2
    assert fake.calls == 1
    assert len(fake.batches[0]) == 4


# ── Opt-in real-model smoke test ─────────────────────────────────────────────


def test_real_model_smoke() -> None:
    """Scores an obviously-entailed pair and an obviously-unrelated pair against a
    real note passage, on the real ``cross-encoder/nli-deberta-v3-base`` checkpoint.

    Opt-in: skipped unless ``HEALTHEE_SUPPORT_MODEL_TESTS=1`` AND
    ``sentence_transformers`` actually imports (the ``eval`` dependency group).

    Observed 2026-09-14 on an RTX 3070 Ti (``torch.cuda.is_available()`` True),
    premise = the `aerobic_decoupling` note's "Cardiovascular drift is real and
    well-characterised..." passage:
      * entailed hypothesis ("Cardiovascular drift is a real, well-documented
        phenomenon during prolonged exercise.") → entailment ≈ **0.9982**
      * unrelated hypothesis ("Bananas are a good source of potassium for marathon
        runners.") → entailment ≈ **0.00027**
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
