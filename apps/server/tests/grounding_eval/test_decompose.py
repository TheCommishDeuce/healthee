"""``tests/grounding_eval/decompose.py`` — pure text splitting, no model, no corpus.

Every case here is deterministic string-in/list-out; no fixture, no monkeypatch, no
NLI. See the module docstring for the heuristics themselves and their known failure
modes; this file exercises the specific behaviours the brief that replaced v1's
whole-sentence scoring called out by name.
"""

from __future__ import annotations

from tests.grounding_eval import decompose


def test_a_short_uncited_framing_clause_is_stripped() -> None:
    sentence = (
        "One caveat that applies to all of the above: this is observational cohort "
        "evidence and healthier people simply tend to move more anyway."
    )
    fragments = decompose.decompose(sentence)
    assert all("One caveat" not in f for f in fragments)
    assert any("tend to move more" in f for f in fragments)


def test_a_long_framing_clause_is_not_stripped() -> None:
    """The clause before the colon is 16 words — over the 12-word cap — so this is
    NOT a framing strip, and the sentence goes to clause-splitting whole."""
    sentence = (
        "That matters here because your strap's deep-sleep minutes are the least "
        "trustworthy number on the card: wrist wearables over-estimate deep sleep."
    )
    fragments = decompose.decompose(sentence)
    assert any("strap's deep-sleep minutes" in f for f in fragments)


def test_a_short_clause_is_not_stripped_when_the_remainder_is_too_short() -> None:
    """The clause is short enough (<= 12 words) but what follows the colon is only
    three words — too little to stand as its own claim — so the strip is refused."""
    sentence = "Two things stand out here today: fatigue and risk."
    working = decompose._strip_framing_clause(sentence)
    assert working == sentence


def test_a_clause_carrying_its_own_citation_is_never_stripped() -> None:
    sentence = "As shown in the note [known_note]: widgets reliably improve grip strength."
    working = decompose._strip_framing_clause(sentence)
    assert working == sentence


def test_em_dash_splits_into_two_fragments() -> None:
    sentence = (
        "Wrist wearables over-estimate deep sleep — single-night stage values agree "
        "with lab polysomnography only sixty to seventy percent of the time."
    )
    fragments = decompose.decompose(sentence)
    assert len(fragments) == 2
    assert fragments[0].startswith("Wrist wearables")
    assert fragments[1].startswith("single-night stage values")


def test_semicolon_splits_into_two_fragments() -> None:
    sentence = "Fragment one carries a real claim here; fragment two carries another one."
    fragments = decompose.decompose(sentence)
    assert len(fragments) == 2


def test_and_splits_a_compound_sentence_even_at_the_cost_of_a_noun_phrase() -> None:
    """Deliberate, documented bluntness: this ALSO splits a plain noun-phrase "and"
    ("resting heart rate and overnight respiratory rate"), not only a clause-level
    one — the module docstring names this as a known, accepted cost."""
    sentence = (
        "The fingerprint of accumulating fatigue is a rise in resting heart rate "
        "and overnight respiratory rate above your usual pattern for several days."
    )
    fragments = decompose.decompose(sentence)
    assert any("resting heart rate" in f for f in fragments)
    assert any("overnight respiratory rate" in f for f in fragments)


def test_a_fragment_under_five_words_is_dropped() -> None:
    sentence = "Grip strength improves and independent trials confirm it works reliably over time."
    fragments = decompose.decompose(sentence)
    assert "Grip strength improves" not in fragments
    assert all(len(f.split()) >= 5 for f in fragments)


def test_an_owner_data_fragment_is_dropped() -> None:
    sentence = (
        "Your resting heart rate was 52 today and independent trials confirm widgets "
        "reliably improve grip strength over many weeks of training."
    )
    fragments = decompose.decompose(sentence)
    assert not any("Your resting heart rate" in f for f in fragments)
    assert any("independent trials confirm" in f for f in fragments)


def test_a_sentence_with_no_splittable_structure_yields_one_fragment_equal_to_itself() -> None:
    sentence = "Widgets have been proven to reliably enhance grip strength in trained adults."
    fragments = decompose.decompose(sentence)
    assert fragments == [sentence]


def test_a_purely_owner_data_sentence_with_no_split_falls_back_to_the_whole_sentence() -> None:
    """Nothing to split on, and the whole sentence reads as arithmetic on the owner's
    own number — the fallback is UNCONDITIONAL (#review fix): "your SRI is 74, which
    meets the established threshold of 70 [note]" is exactly this shape and DOES make a
    checkable claim (the threshold), so reporting zero fragments here would silently
    mark a real, cited claim unsupported for a reason that has nothing to do with the
    note. `decompose` cannot see whether a citation is attached — that is `support.py`'s
    job — so it always keeps something to test."""
    sentence = "Your heart rate was 62 today according to the strap."
    assert decompose.decompose(sentence) == [sentence]


def test_the_sri_threshold_sentence_is_not_swallowed_by_the_owner_data_rule() -> None:
    """The exact false-negative the review caught: a real threshold claim wrapped
    around the owner's own number, with nothing to split on. `quotes_own_measurement`
    correctly flags the WHOLE sentence (it has a number and "Your"), but the sentence
    is exactly the note-grounded half the scorer exists to check — it must survive."""
    sentence = (
        "Your sleep regularity index (SRI) is 74.0, which meets the established "
        "threshold of 70 [sleep_score_implementation_plan]."
    )
    assert decompose.decompose(sentence) == [sentence]


def test_short_and_owner_data_fragments_together_still_fall_back_to_the_sentence() -> None:
    """Every split fragment gets filtered (one too short, one owner-data) — the
    fallback returns the sentence whole rather than reporting zero fragments for a
    claim that has real content, regardless of whether the whole also reads as
    owner-data (the exception for that case is gone — see the module docstring)."""
    sentence = "backed by research and your score was 4 today for the group."
    fragments = decompose.decompose(sentence)
    assert fragments == [sentence]
