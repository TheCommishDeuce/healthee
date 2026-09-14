"""Deterministic decomposition of one cited sentence into atomic, checkable fragments.

A cited answer sentence is routinely a compound bullet: framing about the owner
("That matters here because your…", "One caveat that applies to all of the above:"),
then two or three facts joined by " — ", "; ", " so " or " and ". A cross-encoder NLI
model needs a short, atomic hypothesis — asking it to entail the WHOLE compound
sentence against one passage is why v1's ``support.py`` scored strong evidence at
0.00 (see that module's own history in git blame / the brief that replaced it: a
caffeine-sleep sentence citing ``wearable_sleep_stage_validity`` scored 0.00 against
a note whose Summary said exactly what the sentence claimed).

This module only SPLITS text; it has no model dependency and is fully unit-testable
without torch. ``support.py`` is the only caller.

## The heuristics, and what they get wrong

- **Framing-clause strip.** A clause before the sentence's first ``:`` is dropped
  when it is short (<= 12 words), carries no citation of its own, and what follows
  the colon is itself long enough to stand alone (>= 4 words) — three guards against
  stripping a real clause that merely happens to contain a colon (a ratio, a labelled
  list, a genuinely long lead-in). Only the FIRST colon is ever considered; a second
  one is left alone.
- **Clause splitting** on " — ", "; ", " so ", " and " — the exact joins the coach's
  compound bullets use (measured on the baseline arm). This is a blunt LEXICAL split,
  not a parse: it will split a genuine noun-phrase "and" ("resting heart rate and
  overnight respiratory rate") exactly as readily as a clause-level one. A fragment
  that reads oddly alone is the expected cost of that bluntness, not a bug — see
  ``test_decompose.py`` for cases this gets wrong on purpose, by design, because the
  alternative (a real parse) is exactly the LLM-in-the-loop cost this eval avoids.
- **Short-fragment drop** (< 5 words) removes what a split like that leaves behind
  ("resting heart rate" alone) — too little content for an NLI model to judge as an
  atomic claim.
- **Owner-data drop** reuses ``calibration.quotes_own_measurement``: a fragment that
  is arithmetic on the owner's own numbers ("your HRV was 45 ms last night") cites
  nothing because there is nothing TO cite — no note grounds a personal measurement —
  so it is not something support-scoring can judge either way.
- **Fallback to the whole (post-framing-strip) sentence, unconditionally,** when every
  fragment above got filtered away — INCLUDING when the sentence itself reads as pure
  owner-data. "Your SRI is 74.0, which meets the established threshold of 70
  [sleep_score_implementation_plan]" quotes the owner's own number AND makes a
  checkable claim about a note-defined threshold in the same breath; dropping it
  because ``quotes_own_measurement`` also fires on it would report a claim with a real,
  checkable citation as unsupported for a reason ("nothing left to test") that has
  nothing to do with the cited note — worse than testing the sentence whole, which is
  what v1 did, and the floor this module must never fall below. There is therefore no
  sentence this function reports zero fragments for: an entirely uncited or citation-
  free caller never reaches ``decompose`` at all (``support.py`` only calls it on an
  already-cited sentence), so returning ``[]`` here would only ever manufacture a false
  "nothing to test" for a claim that IS cited.
"""

from __future__ import annotations

import re

from healthee.insights import answer_text, calibration

_FRAMING_MAX_CLAUSE_WORDS = 12
_FRAMING_MIN_REMAINDER_WORDS = 4
_MIN_FRAGMENT_WORDS = 5

# Word-boundary "and"/"so" — `\b` alone keeps this from firing inside "sand" or
# "also" (neither has a word boundary at the right spot), so only the standalone
# conjunction ever splits.
_CLAUSE_SPLIT_RE = re.compile(r"\s*—\s*|;\s+|\bso\b|\band\b")


def _word_count(text: str) -> int:
    return len(text.split())


def _has_citation(text: str) -> bool:
    ids, personal = answer_text.extract_citations(text)
    return bool(ids or personal)


def _strip_framing_clause(sentence: str) -> str:
    """Drop a short, uncited lead-in clause before the sentence's first colon."""
    colon = sentence.find(":")
    if colon == -1:
        return sentence
    clause, remainder = sentence[:colon], sentence[colon + 1 :].strip()
    if not remainder or _has_citation(clause):
        return sentence
    if _word_count(clause) > _FRAMING_MAX_CLAUSE_WORDS:
        return sentence
    if _word_count(remainder) < _FRAMING_MIN_REMAINDER_WORDS:
        return sentence
    return remainder


def _split_clauses(sentence: str) -> list[str]:
    return [part.strip() for part in _CLAUSE_SPLIT_RE.split(sentence) if part.strip()]


def _is_checkable(fragment: str) -> bool:
    """Long enough to carry a claim, and not purely arithmetic on the owner's own data."""
    return _word_count(fragment) >= _MIN_FRAGMENT_WORDS and not calibration.quotes_own_measurement(
        fragment
    )


def decompose(sentence: str) -> list[str]:
    """One cited sentence -> its atomic, independently-checkable fragments.

    Never empty: the owner-data drop applies to SPLIT FRAGMENTS only (a compound
    sentence can carry one arithmetic clause and one citable one), and when every
    fragment is filtered away the fallback is the whole post-framing-strip sentence,
    unconditionally — see the module docstring on why "pure owner-data" is not an
    exception to that fallback.
    """
    working = _strip_framing_clause(sentence)
    fragments = [f for f in _split_clauses(working) if _is_checkable(f)]
    return fragments if fragments else [working]
