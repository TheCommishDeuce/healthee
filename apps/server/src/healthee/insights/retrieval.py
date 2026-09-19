"""Manifest-ranked retrieval — the fix for legacy's dump-all context (hole #3).

Legacy stuffed EVERY ★★★ note in full on every call (``_research_notes_md``,
INTELLIGENCE §5.1) — unbounded, and it grew with the corpus. Here we rank the
manifest by relevance to the question + the metrics in play and embed only the
**top-N full note bodies**, listing the remainder as one-line summaries. The note
COUNT is bounded at any corpus size; the token count is not — a note runs 1.2k–8.8k
tokens, so the same "top 6" measured between 18k and 41k tokens across our surfaces
(task #23). That is why *which* six notes rank matters for cost as well as grounding:
this section is 65–83% of every prompt the product sends.

The ranking signals, strongest first: the note's id named literally · a metric in play ·
an intervention named · an alias matched as a word (separator-insensitive) · a bounded
SIMILARITY signal (Step 2a, below) · content words shared with the note's name/aliases/
summary, capped well below one alias hit. The last two exist because the first four are
all EXPLICIT: when none of them fires, a question can still be perfectly clear to a
person and score zero here — "Should I train hard today or take it easy?" did — so the
weak signals are what stand between a plain question and the alphabet.

## Step 2a — hybrid: a real similarity signal, ADDED alongside the lexical one

An embedding similarity (``embedding_index.note_scores`` — a local, torch-free ONNX
model, the max cosine similarity over a note's passages) was first built to REPLACE the
lexical tie-break, on the theory that a weak word-overlap count was strictly worse than
a real semantic signal. Measured against the 14 held-out paraphrase probes, that theory
was only half true: the two signals catch **different** probes. Lexical alone (today's
shipped ranking, no similarity) already hits ``pp_hrv_spelled``, ``pp_five_hours`` and
``pp_grumpy_morning`` on vocabulary the note's own name/summary happens to share;
similarity alone hits ``pp_espresso`` and ``pp_desk_job``, which share no vocabulary at
all with their target notes. Replacing one with the other traded a net LOSS (10/14 →
9/14) for a gain the corpus didn't actually need to give up. So both signals are
additive: ``score = explicit + LEXICAL_HIT * lexical_hits + SIM_WEIGHT * similarity``.
An explicit hit still dominates both, by construction: :data:`SIM_WEIGHT` tops out at
8.0, :data:`_LEXICAL_HIT` is capped at 4 (:data:`_LEXICAL_CAP`), and one metric or
intervention hit alone (10) already outweighs either at its maximum.

This also means the FALLBACK path — the local embedding model unavailable, similarity
term forced to zero (see :func:`_note_similarities`) — degrades to exactly the ranking
that shipped before this file added similarity at all, lexical tie-break included, not
to the pre-alias-pass alphabet. ``evidence_section`` embeds the top-N notes
unconditionally, as it always has: a bounded-relevance "floor" that would withhold every
note below some similarity threshold was tried and measured (task report) to sit inside
a band where genuinely off-topic and genuinely on-topic questions overlap (~0.62–0.65
either way) — a mechanism that cannot do its job and can silently starve a real question
of every note is worse than none. Out-of-domain questions are the deterministic
pre-classifier's job (INTELLIGENCE.md section 3), not retrieval's.
"""

from __future__ import annotations

import re
from functools import lru_cache

from healthee.core.logging import get_logger
from healthee.insights import embedding_index
from healthee.insights.embedding_index import EmbeddingIndexUnavailableError
from healthee.insights.manifest import GRADE_RANK, ManifestNote, all_notes, prompt_body

log = get_logger(__name__)

DEFAULT_TOP_N = 6

_DIRECT_ID = 100  # the note's id literally named in the question
_METRIC_HIT = 10  # a metric in play is in the note's applies_to_metrics
_INTERVENTION_HIT = 10
_ALIAS_HIT = 5  # an alias phrase appears in the question
_LEXICAL_HIT = 1  # a content word shared with the note's name/aliases/summary
# The lexical signal is CAPPED below one alias hit on purpose: it exists to order notes
# that the explicit signals cannot tell apart, and must never outvote a real one.
_LEXICAL_CAP = 4

# The similarity signal's weight (Step 2a). Calibrated at 0.6 cosine ≈ one alias hit:
# 0.6 * 8.0 = 4.8. Measured over the 30 eval questions + 14 paraphrase probes (Step 2a task
# report), 0.6 sits near the BOTTOM of the on-topic range, not the top —
# bge-small-en-v1.5's cosine similarity against this corpus runs high for almost any
# plausible English sentence (min 0.622, median 0.743, max 0.845 across all 44), so the
# useful discriminative range this weight has to work with is narrow — roughly 4.8 to
# 6.8 points of "excess" score above that baseline. At its theoretical maximum (a
# perfect 1.0, never actually observed) it contributes 8.0 — still below one metric or
# intervention hit (10) and nowhere near an id hit (100), so an explicit signal always
# outranks similarity alone, exactly like the lexical signal's own cap.
SIM_WEIGHT = 8.0

_WORD = re.compile(r"[a-z0-9_]+")

# English function words only — deliberately NOT a health-domain stoplist. The whole
# point of the lexical signal is that a domain word shared between a question and a
# note's summary IS the topical evidence; the words below are the ones that appear in
# every question ever asked and would therefore rank the corpus by summary length.
# Used twice: to pick a question's content words, and to drop an ALIAS that is one of
# these (``fasting_metrics``/``training_stress_score`` both alias "IF" — see _alias_re).
_STOPWORDS = frozenset(
    """about all and any are as at be but by can could did do does doing during each few
    for from get give had has have he how if in into is it its just like long me more
    most much my no not now of off on one only or over should so some tell than that the
    their them then there these they this those to too under up upon us very was we were
    what when where whether which while who why will with without you your
    """.split()  # noqa: SIM905 — one word per line reads; a 90-item list literal does not
)
_MIN_LEXICAL_LEN = 3  # "my", "is", "it" carry no topic; three letters is the floor
_NEVER = re.compile(r"(?!x)x")  # matches nothing, ever — never "everything" by accident


def _tokens(text: str) -> set[str]:
    return set(_WORD.findall(text.lower()))


def _content_tokens(text: str) -> frozenset[str]:
    """The words in ``text`` that could plausibly name a topic."""
    return frozenset(
        t for t in _WORD.findall(text.lower()) if len(t) >= _MIN_LEXICAL_LEN and t not in _STOPWORDS
    )


def _alias_hits(note: ManifestNote, q_text: str) -> int:
    """How many of ``note``'s aliases appear in the question AS WORDS.

    This used to be a bare substring test (``alias.lower() in q_text``), which is not a
    topical signal at all once an alias is short: ``critical_speed`` carries the aliases
    ``W`` and ``D``, so it matched any question containing the letter w or d — i.e. very
    nearly every question in English. Measured (task #23), that note was ranked into the
    top-6 and embedded IN FULL — 6,707 tokens — on **6 of 11** representative surface
    prompts, including "how has my sleep been this week?". A note about running critical
    power was 16% of the daily-action prompt, bought by two letters.

    That is a grounding defect first and a cost defect second: those tokens displaced a
    note that could have grounded the answer, and the coach then spent a whole extra
    round on ``get_knowledge`` fetching the note retrieval should have supplied (each
    round is another ~37k input tokens).

    Word boundaries were the fix and nothing more: an acronym alias still matches its own
    word (``HRV`` in "why is my hrv low"), a phrase alias still matches its phrase, and a
    letter no longer matches the inside of an unrelated word. It does give up matching
    inflections (alias ``sleep`` no longer hits "sleeping"), which is a real but small
    loss — measured across those 11 prompts, every note this rule stopped matching had
    been matched by a substring that was not a topical signal.

    A SECOND defect lived in the same line and survived that fix, because it was never
    about substrings: separators. See :func:`_alias_re`.
    """
    return sum(1 for alias in note.aliases if _alias_re(alias).search(q_text))


@lru_cache(maxsize=1024)
def _alias_re(alias: str) -> re.Pattern[str]:
    """``alias`` as a word-bounded, SEPARATOR-INSENSITIVE pattern, compiled once.

    The separator class is the second half of the alias fix, and it is a defect that
    PREDATES the word-boundary one rather than a consequence of it (measured both ways:
    under the old bare-substring test ``"resting-heart-rate" in "my resting heart rate"``
    was already False). Aliases are written the way the source document spells them —
    ``resting-heart-rate``, ``critical-speed``, ``time-restricted eating``, ``16:8`` —
    and people ask in spaces. Literal matching therefore made ``resting_heart_rate``
    unreachable for the exact phrase "resting heart rate", which is how the coach's RHR
    question in VERIFICATION_2026_08_01 §3 burned a whole ``get_knowledge`` round (~33k
    tokens, a third of that question's cost) fetching the note retrieval should have
    handed it.

    Any run of non-alphanumerics matches any other, so one alias spelling covers all of
    them. Word boundaries stay exactly as they were — a letter still cannot match inside
    a word, which is the property the previous fix bought.

    An alias that IS an English function word is dropped, and that is the same defect as
    the one-letter alias in a third disguise: ``fasting_metrics`` and
    ``training_stress_score`` both carry the alias ``IF`` (intermittent fasting /
    intensity factor), so any prompt containing the word "if" bought two full notes —
    including the shipped ``metric_insight`` prompt, which says "If it's off my
    baseline". Word boundaries cannot help, because "if" is a whole word. A note is not
    made unreachable by this: its other aliases, its metrics and its id all still rank it.
    """
    if alias.lower().strip() in _STOPWORDS:
        return _NEVER
    parts = [re.escape(p) for p in re.split(r"[^a-z0-9]+", alias.lower()) if p]
    if not parts:  # an alias of pure punctuation matches nothing, never everything
        return _NEVER
    return re.compile(r"(?<!\w)" + r"[^a-z0-9]+".join(parts) + r"(?!\w)")


@lru_cache(maxsize=256)
def _lexical_terms(note: ManifestNote) -> frozenset[str]:
    """The note's own topic words: its name, its aliases and its one-line summary.

    Not the body: the body would make almost every note share almost every word, and the
    signal is meant to be weak and cheap. Cached per note (the manifest is immutable).
    """
    return _content_tokens(" ".join((note.name, note.summary, *note.aliases)))


def _lexical_hits(note: ManifestNote, q_content: frozenset[str]) -> int:
    """Shared content words, capped — the tie-break that replaced the alphabet.

    Before this, a question whose subject no metric or alias covered scored ZERO against
    every note, and ``rank_notes``'s deterministic fallback then handed the model the
    alphabetically-first Established notes. Measured on the shipped corpus, "Should I
    train hard today or take it easy?" retrieved alcohol_sleep, behavior_change,
    cadence_intensity, caffeine_sleep, critical_speed and environmental_stress — six full
    notes, ~30k tokens, chosen by spelling. The model was then asked to ground an
    intensity decision in them, which is a grounding failure wearing an ordering bug's
    clothes: the honest fallback it produced was the correct output for the evidence it
    was given.

    Weak by construction (:data:`_LEXICAL_CAP` sits below one alias hit): it may order
    notes the explicit signals cannot distinguish, and may never outrank one of them.
    Kept ADDITIVE alongside Step 2a's similarity signal (see the module docstring) rather
    than replaced by it — measured, the two catch different held-out paraphrases.
    """
    return min(len(q_content & _lexical_terms(note)), _LEXICAL_CAP)


_warned_embedding_unavailable = False


def _note_similarities(question: str) -> dict[str, float]:
    """Best-passage cosine similarity per note for ``question`` — ``{}`` on fallback.

    ``{}`` specifically when the local embedding model is unavailable: logged once per
    process at WARNING (naming the fix), never re-raised. A health-answer surface that
    cannot load the ONNX model must still answer from explicit + lexical signals rather
    than go down — see the module docstring on why that fallback is the pre-Step 2a ranking,
    not the pre-alias-pass alphabet. Any OTHER exception (a corrupt passage, a numpy
    shape bug) is a real bug in this product's own code and propagates unchanged.
    """
    global _warned_embedding_unavailable
    try:
        return embedding_index.note_scores(question)
    except EmbeddingIndexUnavailableError as exc:
        if not _warned_embedding_unavailable:
            log.warning(
                "embedding index unavailable (%s) — retrieval falls back to "
                "explicit + lexical ranking only for the rest of this process",
                exc,
            )
            _warned_embedding_unavailable = True
        return {}


def reset_embedding_warning() -> None:
    """Test seam only: clears the once-per-process fallback-warning latch."""
    global _warned_embedding_unavailable
    _warned_embedding_unavailable = False


def _score(
    note: ManifestNote,
    q_tokens: set[str],
    q_text: str,
    metrics: set[str],
    q_content: frozenset[str],
    note_sim: dict[str, float],
) -> float:
    """Relevance of one note to the question + active metrics (higher = better)."""
    score = 0.0
    if note.id and note.id in q_tokens:
        score += _DIRECT_ID
    score += _METRIC_HIT * len(metrics.intersection(note.applies_to_metrics))
    score += _INTERVENTION_HIT * sum(1 for iv in note.applies_to_interventions if iv in q_tokens)
    score += _ALIAS_HIT * _alias_hits(note, q_text)
    score += _LEXICAL_HIT * _lexical_hits(note, q_content)
    score += SIM_WEIGHT * note_sim.get(note.id, 0.0)
    return score


def rank_notes_with_scores(
    question: str, metrics: list[str] | None = None
) -> list[tuple[ManifestNote, float]]:
    """Every note, most relevant first, PAIRED with the score that ordered it.

    The same ordering :func:`rank_notes` returns (that function is now a one-line
    projection of this one) — exposed with its score for ``insights/evidence.py``'s
    per-note token-budget split (Step 2b), which weights the coach's top-N notes by
    actual relevance rather than by bare position.
    """
    q_text = question.lower()
    q_tokens = _tokens(question)
    q_content = _content_tokens(question)
    metric_set = set(metrics or [])
    note_sim = _note_similarities(question)
    scored = [
        (n, _score(n, q_tokens, q_text, metric_set, q_content, note_sim)) for n in all_notes()
    ]
    scored.sort(key=lambda pair: (-pair[1], -GRADE_RANK.get(pair[0].grade, 0), pair[0].id))
    return scored


def rank_notes(question: str, metrics: list[str] | None = None) -> list[ManifestNote]:
    """All notes, most relevant first; ties break toward stronger evidence grades.

    A pure reorder (legacy semantics) — bounding to top-N happens in
    ``evidence_section``. Deterministic: equal scores fall back to grade then id.

    The id fallback is a REPRODUCIBILITY device, not a ranking: it makes the same
    question retrieve the same notes twice. It used to decide the whole top-6 whenever
    nothing scored (see :func:`_lexical_hits`), which is the alphabet answering a health
    question. It is still the last resort, and now it is reached far less often.
    """
    return [n for n, _s in rank_notes_with_scores(question, metrics)]


def evidence_section(
    question: str, metrics: list[str] | None = None, *, top_n: int = DEFAULT_TOP_N
) -> tuple[str, list[str]]:
    """The EVIDENCE NOTES markdown + the ids embedded in full.

    Top-N notes appear with their body and grade tag; the rest are one-line
    ``[id] (Grade): summary`` entries so the model knows they exist and are citable
    without paying their full token cost.

    The embedded body is ``prompt_body`` — the note minus its bibliography, which the
    model cannot cite (see that function). ``note_body`` remains the whole note for the
    human-facing reader.
    """
    ranked = rank_notes(question, metrics)
    if not ranked:
        return ("", [])
    top, rest = ranked[:top_n], ranked[top_n:]
    parts = [
        "# EVIDENCE NOTES",
        "Cite ONLY by id: `[note_id]`. Each note shows its evidence grade — match "
        "your wording to it. If no note covers a claim, write "
        "`No strong evidence in our base for this.`",
    ]
    for n in top:
        parts.append(f"\n## `[{n.id}]` ({n.grade}) — {n.name}\n{prompt_body(n.id)}")
    if rest:
        parts.append("\n## Other citable notes (summaries only)")
        parts.extend(f"- `[{n.id}]` ({n.grade}): {n.summary}" for n in rest)
    return ("\n".join(parts), [n.id for n in top])
