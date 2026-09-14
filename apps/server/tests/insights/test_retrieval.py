"""Manifest-ranked retrieval — the fix for legacy dump-all (hole #3), now hybrid (Step 2a).

Proves a metric's own notes rank to the top and that the full-note count is
bounded (top-N), with the remainder present only as one-line summaries.

The alias tests below are the guard on task #23's finding: an alias was matched as a
bare SUBSTRING, so ``critical_speed``'s aliases ``W`` and ``D`` put a 6,707-token note
about running critical power into the top-6 of 6 of 11 representative prompts — 16% of
the daily-action prompt, bought by two letters. Word boundaries are the fix, and these
pin both halves of it: the letter no longer matches, the acronym still does.

Task #94 then found two more, both of which changed WHICH notes ground an answer:
separators (an alias spelled ``resting-heart-rate`` could not match the phrase "resting
heart rate", so the note was unreachable for its own name) and the all-zero tie-break
(a question no explicit signal covered was answered with the alphabetically-first
Established notes). The tests for those pin the behaviour AND its bounds — particularly
that neither the lexical signal nor the similarity signal can ever outvote an explicit
one.

## Step 2a — similarity is ADDITIVE alongside the lexical signal, not a replacement

Measured against the 14 held-out paraphrase probes, the lexical and embedding
signals catch DIFFERENT probes (the module docstring has the numbers), so both stay:
``score = explicit + lexical + SIM_WEIGHT * similarity``. Every test in this file that
does not care about the similarity term runs with it STUBBED to ``{}``
(:func:`_no_similarity`, autouse) — which makes the hybrid score degrade to exactly the
pre-Step 2a explicit+lexical score, so every pre-existing test below is unchanged in what it
proves. Tests that DO care about the similarity signal override the stub explicitly.
Nothing here reaches the real ``fastembed`` model, network, or disk — see
``test_embedding_index.py`` for that layer's own tests, and its opt-in real-model smoke
test.
"""

from __future__ import annotations

import logging
import re

import pytest

from healthee.insights import retrieval
from healthee.insights.embedding_index import EmbeddingIndexUnavailableError
from healthee.insights.manifest import ManifestNote, all_notes
from healthee.insights.morning import DAILY_ACTION_METRICS, DAILY_ACTION_PROMPT
from healthee.insights.retrieval import (
    _ALIAS_HIT,
    _LEXICAL_CAP,
    _METRIC_HIT,
    SIM_WEIGHT,
    _alias_hits,
    _content_tokens,
    _score,
    _tokens,
    evidence_section,
    rank_notes,
)


@pytest.fixture(autouse=True)
def _no_similarity(monkeypatch: pytest.MonkeyPatch) -> None:
    """Default stub: every note has zero similarity, so hybrid == explicit+lexical.

    A test that wants a real (fake) similarity calls ``monkeypatch.setattr`` again with
    its own dict or exception — the later patch wins, exactly like any other fixture
    override in this test suite.
    """
    monkeypatch.setattr(retrieval.embedding_index, "note_scores", lambda _q: {})
    retrieval.reset_embedding_warning()


def _relevance(note_id: str, question: str, metrics: tuple[str, ...] = ()) -> float:
    note = next(n for n in all_notes() if n.id == note_id)
    return _score(
        note, _tokens(question), question.lower(), set(metrics), _content_tokens(question), {}
    )


def test_metric_notes_rank_to_the_top() -> None:
    ranked = rank_notes("how are my steps", metrics=["steps_total"])
    top_ids = {n.id for n in ranked[:3]}
    # Every note that applies to steps_total should be among the highest-ranked.
    assert {"steps_mortality", "exercise_mortality"} & top_ids


def test_direct_id_mention_ranks_first() -> None:
    ranked = rank_notes("tell me about alcohol_sleep")
    assert ranked[0].id == "alcohol_sleep"


def test_evidence_section_bounds_full_notes() -> None:
    md, top_ids = evidence_section("steps and activity", metrics=["steps_total"], top_n=3)
    assert len(top_ids) == 3  # only N full notes embedded
    assert md.count("\n## `[") == 3  # exactly N full-note headers
    assert "Other citable notes (summaries only)" in md  # the rest are summaries


def test_evidence_section_is_empty_without_a_corpus_match_still_lists_notes() -> None:
    """``evidence_section`` embeds top-N UNCONDITIONALLY (no relevance floor, Step 2a).

    A floor was tried and measured: the on-topic/off-topic similarity bands overlap
    (~0.62–0.65 either way over the 44-question task report), so a threshold there can
    silently starve a genuine question of every note. Every note stays reachable —
    the ranker only ever reorders.
    """
    md, top_ids = evidence_section("anything", metrics=[])
    assert top_ids  # notes are always available to cite (ranker only reorders)
    assert "# EVIDENCE NOTES" in md


def test_a_single_letter_alias_does_not_match_inside_a_word() -> None:
    """``critical_speed`` aliases ``W``/``D``; "this week … today" is not critical power.

    Asserted on the SCORE rather than the ranking: what the word-boundary rule claims is
    that the note stops being scored as *relevant*, and that is what this reads. (When it
    was written, a zero-scoring note could still surface in a top-6 on the alphabetical
    tie-break — that was the separate weakness #94b then fixed below.)

    The premise is asserted first: if the corpus ever drops those one-letter aliases the
    test stops proving anything, and it should say so rather than pass vacuously.
    """
    note = next(n for n in all_notes() if n.id == "critical_speed")
    assert any(len(a) == 1 for a in note.aliases), note.aliases
    assert _relevance("critical_speed", "How has my sleep been this week? One move today.") == 0


def test_the_daily_action_prompt_no_longer_embeds_a_critical_power_note() -> None:
    """The end-to-end version of the same fact, on a real shipped prompt.

    Measured before the fix: ``critical_speed`` was ranked into this prompt's top-6 and
    embedded IN FULL — 6,707 tokens, 16% of a ~42k prompt, every owner, every night.
    """
    top = [n.id for n in rank_notes(DAILY_ACTION_PROMPT, DAILY_ACTION_METRICS)[:6]]
    assert "critical_speed" not in top


def test_an_acronym_alias_still_matches_its_own_word() -> None:
    """The fix must not cost real matches: HRV is how people ask about HRV."""
    assert _relevance("heart_rate_variability", "why is my hrv low lately?") > 0
    top = [n.id for n in rank_notes("why is my hrv low lately?")[:5]]
    assert "heart_rate_variability" in top


def test_a_phrase_alias_still_matches_its_phrase() -> None:
    ranked = rank_notes("how does alcohol before bed affect sleep?")
    assert ranked[0].id == "alcohol_sleep"


# ── #94a · an alias is matched however its separators are spelled ────────────


def test_a_hyphenated_alias_matches_the_phrase_as_a_person_writes_it() -> None:
    """``resting_heart_rate`` was unreachable for the words "resting heart rate".

    Its aliases are spelled the way the source document spells them
    (``resting-heart-rate``), and people ask in spaces — so the note that IS the answer
    scored zero, and the coach spent a whole ``get_knowledge`` round (~33k input tokens)
    fetching what retrieval should have handed it (VERIFICATION_2026_08_01 §3).

    The premise is asserted first: if the corpus ever adds a spaced alias this test would
    pass for the wrong reason, and it should say so rather than go quietly green.
    """
    note = next(n for n in all_notes() if n.id == "resting_heart_rate")
    assert "resting heart rate" not in {a.lower() for a in note.aliases}, note.aliases
    assert "resting-heart-rate" in {a.lower() for a in note.aliases}
    question = "What is my resting heart rate over the last week?"
    assert _relevance("resting_heart_rate", question) >= _ALIAS_HIT
    assert rank_notes(question)[0].id == "resting_heart_rate"


def test_the_separator_class_is_symmetric_across_spellings() -> None:
    """One alias spelling has to cover all of them, or the corpus decides reachability.

    The underscore spelling is deliberately NOT in this comparison: it is the note's id,
    so it scores an id hit (100) on top and is a different signal, not an asymmetry.
    """
    spaced = _relevance("resting_heart_rate", "my resting heart rate")
    hyphenated = _relevance("resting_heart_rate", "my resting-heart-rate")
    assert spaced == hyphenated > 0


def test_a_separator_is_still_required_between_the_words() -> None:
    """Insensitive to WHICH separator, not to its absence — "restingheartrate" is not it."""
    assert _relevance("resting_heart_rate", "my restingheartrate today") == 0


# ── #94b · an all-zero score no longer hands over the alphabet ───────────────


def test_a_plain_question_no_longer_retrieves_the_alphabetically_first_notes() -> None:
    """Measured before: "should I train hard today" scored ZERO against all 74 notes.

    The deterministic id tie-break then chose the top-6, so the model was asked to ground
    an intensity decision in alcohol_sleep, behavior_change_and_personalization,
    cadence_intensity, caffeine_sleep, critical_speed and environmental_stress — ~30k
    tokens of full notes, selected by spelling. The honest fallback it produced was the
    right output for that evidence, which is why this reads as a grounding fix.

    Run with the similarity stub still at ``{}`` (no Step 2a signal at all) — this is the
    EXPLICIT+LEXICAL guarantee the alias pass already bought, unaffected by hybrid
    scoring, and exactly what the fallback path degrades to when the model is down.
    """
    question = "Should I train hard today or take it easy? Base it on my recovery."
    top = [n.id for n in rank_notes(question)[:6]]
    assert "recovery_readiness" in top
    assert "alcohol_sleep" not in top
    assert "cadence_intensity" not in top


def test_the_lexical_signal_can_never_outvote_an_alias_hit() -> None:
    """The cap is the whole safety argument for adding a fuzzy signal to retrieval.

    Synthetic notes, because the point is a BOUND on the scoring rule rather than a fact
    about today's corpus: a note that merely shares vocabulary must lose to a note the
    question actually named, however much vocabulary it shares.
    """
    question = "how does alcohol affect deep sleep architecture and recovery overnight"
    named = ManifestNote(
        id="named",
        name="Alcohol",
        grade="Established",
        summary="",
        path="",
        category="x",
        aliases=("alcohol",),
    )
    wordy = ManifestNote(
        id="wordy",
        name="Deep sleep architecture recovery overnight",
        grade="Established",
        summary="deep sleep architecture recovery overnight affect does",
        path="",
        category="x",
    )
    args = (_tokens(question), question.lower(), set(), _content_tokens(question), {})
    assert _score(wordy, *args) == _LEXICAL_CAP
    assert _score(named, *args) > _score(wordy, *args)


def test_function_words_alone_score_nothing() -> None:
    """Otherwise every question would rank the corpus by how long its summaries are.

    Written first as "no note scores anything", which FAILED — and the failure was the
    third instance of the two-letter-alias defect: ``fasting_metrics`` and
    ``training_stress_score`` both alias ``IF``, so the English word "if" bought two full
    notes on any prompt containing it (the shipped ``metric_insight`` prompt says "If
    it's off my baseline"). Word boundaries could never have caught that one — "if" is a
    whole word. An alias that is a function word is now dropped, so this reads as
    written. Run with the similarity stub at ``{}`` — a real embedding rarely scores
    exactly 0.0, so this guarantee lives at the explicit+lexical layer, same as before
    Step 2a existed.
    """
    question = "what should I do about this and that, if you could tell me?"
    assert _content_tokens(question) == frozenset()
    assert max(_relevance(n.id, question) for n in all_notes()) == 0


def test_an_alias_that_is_an_english_function_word_never_matches() -> None:
    """The premise, asserted so this cannot pass vacuously if the corpus drops ``IF``."""
    fasting = next(n for n in all_notes() if n.id == "fasting_metrics")
    assert "IF" in fasting.aliases
    # Read on the ALIAS hits, not the total: the note may still pick up a weak lexical
    # point for a word its summary happens to share, which is the intended behaviour.
    assert _alias_hits(fasting, "tell me if my recovery is fine") == 0
    assert _alias_hits(fasting, "how does intermittent fasting affect me") > 0


def test_the_embedded_notes_carry_no_bibliography() -> None:
    """The evidence section embeds ``prompt_body``: no note is citable by paper."""
    md, _ids = evidence_section("how are my steps", metrics=["steps_total"])
    assert not re.search(r"^##\s+(?:key\s+)?references\b", md, re.I | re.M)


# ── Step 2a · the similarity signal is additive, bounded, and falls back honestly ──


def test_a_similarity_hit_reorders_otherwise_tied_notes(monkeypatch: pytest.MonkeyPatch) -> None:
    """Two notes with zero explicit AND zero lexical signal: the model's pick wins."""
    all_ids = [n.id for n in all_notes()]
    a, b = all_ids[0], all_ids[1]
    monkeypatch.setattr(retrieval.embedding_index, "note_scores", lambda _q: {a: 0.9, b: 0.1})
    ranked = rank_notes("zzqx flurbnop wibbleplex")
    assert ranked[0].id == a


def test_the_similarity_signal_can_never_outvote_a_metric_or_id_hit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Step 2a's whole safety argument: however strong the similarity, it cannot beat an
    explicit metric hit, let alone an id hit — this is what makes it safe to trust a
    real (if imperfect) model instead of hand-tuned vocabulary alone."""
    named = ManifestNote(
        id="named", name="Named", grade="Established", summary="", path="", category="x"
    )
    monkeypatch.setattr(retrieval.embedding_index, "note_scores", lambda _q: {"named": 1.0})
    q_tokens, q_text = _tokens("does this matter"), "does this matter"
    q_content = _content_tokens("does this matter")
    max_sim_score = _score(named, q_tokens, q_text, set(), q_content, {"named": 1.0})
    assert max_sim_score == pytest.approx(SIM_WEIGHT)
    assert max_sim_score < _METRIC_HIT
    metric_note = ManifestNote(
        id="metric_note",
        name="Metric",
        grade="Established",
        summary="",
        path="",
        category="x",
        applies_to_metrics=("steps_total",),
    )
    metric_score = _score(metric_note, q_tokens, q_text, {"steps_total"}, q_content, {})
    assert metric_score > max_sim_score


def test_a_strong_similarity_is_worth_about_one_alias_hit() -> None:
    """Calibration point named in the module docstring: 0.6 cosine ≈ one alias hit."""
    note = ManifestNote(id="n", name="N", grade="Established", summary="", path="", category="x")
    contribution = _score(note, set(), "", set(), frozenset(), {"n": 0.6})
    assert contribution == pytest.approx(_ALIAS_HIT, abs=1.0)


def test_embedder_unavailable_falls_back_to_the_explicit_and_lexical_ranking(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The fallback is TODAY'S shipped ranking (explicit + lexical), not the alphabet —
    Step 2a's similarity term simply drops out, leaving the alias pass's own protection."""

    def _boom(_question: str) -> dict[str, float]:
        raise EmbeddingIndexUnavailableError("simulated: no model file, no network")

    monkeypatch.setattr(retrieval.embedding_index, "note_scores", _boom)
    question = "Should I train hard today or take it easy? Base it on my recovery."
    fallback_ranking = [n.id for n in rank_notes(question)]

    monkeypatch.setattr(retrieval.embedding_index, "note_scores", lambda _q: {})
    explicit_and_lexical_ranking = [n.id for n in rank_notes(question)]
    assert fallback_ranking == explicit_and_lexical_ranking
    assert "recovery_readiness" in fallback_ranking[:6]
    assert "alcohol_sleep" not in fallback_ranking[:6]


def test_the_fallback_warning_is_logged_once_per_process(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    def _boom(_question: str) -> dict[str, float]:
        raise EmbeddingIndexUnavailableError("simulated: no model file, no network")

    monkeypatch.setattr(retrieval.embedding_index, "note_scores", _boom)
    with caplog.at_level(logging.WARNING, logger="healthee.insights.retrieval"):
        rank_notes("first question")
        rank_notes("second question")
    warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert len(warnings) == 1
    assert "embedding index unavailable" in warnings[0].message


def test_an_unrelated_exception_is_not_swallowed(monkeypatch: pytest.MonkeyPatch) -> None:
    """Only ``EmbeddingIndexUnavailableError`` degrades gracefully — anything else
    (a real bug) must propagate, per the module docstring's failure policy."""

    def _boom(_question: str) -> dict[str, float]:
        raise ValueError("simulated corpus/numpy bug, not a model-load failure")

    monkeypatch.setattr(retrieval.embedding_index, "note_scores", _boom)
    with pytest.raises(ValueError, match="simulated corpus/numpy bug"):
        rank_notes("does this propagate")
