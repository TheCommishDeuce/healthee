"""The coach's answer as DATA — claims carry their ids, and we render the prose (#128).

## The measured problem

Until this module existed the coach answered in free prose carrying an inline
``[note_id]`` convention, and the blocking validator then checked whether the model had
remembered it. Measured on ``tests/grounding_eval`` (INTELLIGENCE §9.5), a cheaper model
on the same commit lost 3 of 6 knowledge answers to *"Interpretive sentence lacks a
citation"* while matching the expensive one everywhere the output was already
STRUCTURED. Nothing incorrect ever shipped — the validator caught all of it and served
the honest fallback — so what the convention costs is **availability**, and the cost is
instruction-following on a formatting rule rather than health knowledge.

## The fix is a shape, not a nudge

An uncited interpretive claim is now **impossible to express** rather than possible to
forget. The model returns:

    {"coach_answer": {"opening": "<description only>",
                      "claims": [{"text": ..., "note_ids": [...], "grade": "Probable"}]}}

and :func:`render` writes the prose. Two structural consequences follow, and neither
depends on the model remembering anything:

* **Every claim ships with its ids attached**, because the renderer attaches them — to
  every sentence of the claim, not just the last one. A claim the model marks uncitable
  (``note_ids: []``) ships carrying ``prompts.NO_EVIDENCE``'s own words in the same
  sentence, which is the honest escape the validator already accepts. There is no third
  outcome: a claim is cited, or it is marked unsupported.
* **Interpretation cannot hide in the frame.** ``opening`` is free text, so it is checked
  here for the one thing that would reopen the hole — an interpretive sentence — using
  ``calibration``'s own vocabulary and ``validator``'s own two exemptions, so "your RHR
  averaged 54" stays legal and "your recovery is low" is redirected into ``claims``. This
  is an ADDITIONAL constraint, never a replacement: the rendered text still goes through
  every answer gate unchanged (``pipeline.answer_gates``).

## The declared grade is replaced, not trusted and not refused

``grade`` is the same hole INTELLIGENCE section 5.6 records for recs: a self-declared
grade nobody compares against the cited notes lets a Contested claim ship labelled
Established. :func:`_with_provable_grade` resolves the provable grade from the strictest
cited note in the manifest and puts THAT on the claim. It used to refuse an overclaim and
nudge the model to redeclare; measured, that was the commonest cause of a rewritten turn,
and the redeclaration bought nothing the server did not already know. Under-claiming
stays allowed — declaring Emerging while citing Established costs the answer a hedge it
did not owe, which is honest. Nothing here *rewrites* a sentence: the hedge the wording
owes is the validator's call, made on the rendered text against the same note grades.

Nothing here validates. It parses, checks its own shape, and renders; the issues it
returns travel to ``pipeline._structure_gate`` through ``AnswerContext``, so they obey
exactly the same nudge-then-honest-fallback policy every other issue does.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

from healthee.core.knowledge import GRADE_RANK
from healthee.core.logging import get_logger
from healthee.insights import manifest
from healthee.insights.answer_text import sentence_units
from healthee.insights.calibration import INTERPRETIVE_RE, quotes_own_measurement, reports_only

log = get_logger(__name__)

ROOT_KEY = "coach_answer"

# The owner-subjects the answer states a VALUE for (#129). A second declared field for the
# same reason the ids became one: a claim about the owner's own data cites nothing, so
# nothing checked it, and asking the model to declare what its answer is ABOUT is a
# question it can answer — unlike asking it to classify its own sentences. The gate over
# it is ``personal_claims``; parsing stops here.
ASSERTS_KEY = "asserts"

# The escape a claim with no citable evidence ships under — `prompts.SYSTEM_PROMPT`'s
# own sentence, lower-cased and joined into the claim so it lands in the SAME sentence
# unit. `calibration.HONEST_ESCAPE_RE` matches it; a separate sentence would not help,
# because the rules are enforced per sentence and the claim would still be uncited.
NO_EVIDENCE = "no strong evidence in our base for this"

# The instruction lives beside the parser that enforces it, so the two cannot drift into
# describing different shapes. It is APPENDED to the system turn (``coach._initial_messages``)
# exactly as the context and evidence blocks are — ``docs/COACH_PROMPT.md`` is pinned
# byte-for-byte and stays the voice; this is the envelope that voice arrives in.
ANSWER_SHAPE = f"""\
# HOW TO ANSWER (the output contract — not optional)

When you are ready to answer rather than call a tool, reply with ONE JSON object and \
nothing else:

{{"{ROOT_KEY}": {{
  "opening": "One plain line REPORTING their own numbers. Description only: no \
interpretation, no advice, no 'because' / 'suggests' / 'may' / 'should' / 'is low'. \
Omit it if you have no number to report.",
  "claims": [
    {{"text": "One sentence. EVERY interpretation, mechanism, comparison to research, \
confound, caveat and the concrete next step goes here — never in opening.",
     "note_ids": ["ids from EVIDENCE NOTES that support THIS sentence"],
     "grade": "the grade of the WEAKEST note you cited: Established | Probable | \
Emerging | Contested | Myth"}}
  ],
  "{ASSERTS_KEY}": ["every metric key or logged kind (rhr_daily, alcohol, ...) this answer \
states a VALUE, count, date or comparison for from THEIR data — anywhere in it, opening \
included"]
}}}}

- Do NOT write `[note_id]` inside `text`; the ids are a field and are rendered for you. \
A `[personal_finding:...]` tag is the one thing you still write inline.
- `"note_ids": []` is honest and allowed — the sentence then ships marked \
"{NO_EVIDENCE}". Never invent an id to avoid that.
- `"{ASSERTS_KEY}": []` when you assert none — an answer that is only research, or that \
says data is MISSING, asserts nothing: "you have 0 logged alcohol entries" declares \
nothing, while "you logged alcohol yesterday" declares `alcohol`. Declaring a value for \
something no tool returned is how an answer gets discarded whole.
- Order the claims the way you want them read, biggest lever first, next step last. \
Everything above about truth, calibration, confounds and tools still binds; only the \
envelope changed."""

_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")
_TERMINATORS = ".!?"
# A bracket the model wrote inline that is JUST note ids — redundant now that ids are a
# field, and rendering both would print every citation twice. `[personal_finding:…]` has
# a colon, so it never matches and stays exactly where the model put it.
_NOTE_BRACKET_RE = re.compile(r"\s*\[[a-z0-9_]+(?:\s*,\s*[a-z0-9_]+)*\]")
_FENCE_RE = re.compile(r"```(?:json)?", re.IGNORECASE)


@dataclass(frozen=True)
class Claim:
    """One interpretive sentence plus the evidence it rests on and the grade it asserts."""

    text: str
    note_ids: tuple[str, ...] = ()
    grade: str = ""


@dataclass(frozen=True)
class CoachAnswer:
    """A parsed coach answer: a descriptive frame, the claims, and what it asserts.

    ``asserts`` is answer-wide rather than per claim because the personal-claim gate's
    verdict is per SUBJECT — "you have no alcohol" — never per sentence, and because the
    fabrication that motivated it (#129) landed in ``opening``, which is the field whose
    whole job is to report the owner's numbers. One list covers both halves of the answer
    and asks the model for one thing instead of two.
    """

    opening: str = ""
    claims: tuple[Claim, ...] = ()
    asserts: tuple[str, ...] = ()


def parse(raw: str) -> tuple[CoachAnswer | None, tuple[str, ...]]:
    """Read one model turn into an answer + the structural issues it has.

    ``None`` with issues means "this turn is not an answer in the contract" — the driver
    nudges and asks again, and the honest fallback ships if it never arrives. It is never
    treated as prose: falling back to the free-text path on a malformed payload would
    reinstate exactly the convention this module replaces, on the days it is most likely
    to have been ignored.
    """
    payload = _json_object(raw)
    if payload is None:
        return None, ("Answer was not the JSON object this surface requires: see the shape above.",)
    body = payload.get(ROOT_KEY)
    if not isinstance(body, dict):
        return None, (f"Answer JSON has no `{ROOT_KEY}` object: it is the only accepted shape.",)
    opening = body.get("opening") or ""
    claims, issues = _claims(body.get("claims"))
    asserts, assert_issues = _asserts(body.get(ASSERTS_KEY))
    opening = opening.strip() if isinstance(opening, str) else ""
    issues += _opening_issues(opening) + assert_issues
    if not opening and not claims:
        issues += ("Answer carried no opening and no claims: there is nothing to say.",)
    return CoachAnswer(opening=opening, claims=claims, asserts=asserts), issues


def _asserts(raw: object) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """The declared owner-subjects, plus the issue when the field is not a list of names.

    A MISSING field parses to ``()`` without an issue, and that is deliberate: the honest
    answer for most questions is that nothing personal is asserted, and failing an answer
    for omitting an empty list would spend a retry on punctuation. A field of the wrong
    SHAPE is a different thing — the model tried to declare something and we cannot read
    it, so it is an issue rather than a silent empty.
    """
    if raw is None:
        return (), ()
    if not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        return (), (
            f"Answer `{ASSERTS_KEY}` was not a list of metric/logged-kind names: use [] if none.",
        )
    return tuple(item.strip() for item in raw if item.strip()), ()


def render(answer: CoachAnswer) -> str:
    """The prose the owner reads — every claim sentence carrying its ids or the escape.

    THE guarantee of this module, and the reason it is one function: there is no branch
    here that emits a claim's words without also emitting what grounds them.
    """
    lines = [answer.opening] if answer.opening else []
    bullets = [f"- {_cited(claim)}" for claim in answer.claims]
    if bullets:
        lines.append("\n".join(bullets))
    return "\n\n".join(lines)


def _cited(claim: Claim) -> str:
    """One claim as prose: each of its sentences ends in its ids, or in the escape."""
    body = _NOTE_BRACKET_RE.sub("", claim.text).strip()
    parts = [p for p in _SENTENCE_SPLIT_RE.split(body) if p.strip()]
    return " ".join(_cite_sentence(part, claim.note_ids) for part in parts or [body])


def _cite_sentence(sentence: str, note_ids: tuple[str, ...]) -> str:
    """Attach the citation INSIDE the sentence, before its terminator.

    Before it, not after: ``answer_text.truncation_issue`` reads the last line for a
    sentence terminator, and "…fitness [note_id]" ends in a bracket — a perfectly
    complete answer refused as truncated.
    """
    stem = sentence.strip()
    terminator = "."
    if stem and stem[-1] in _TERMINATORS:
        stem, terminator = stem[:-1].rstrip(), stem[-1]
    if note_ids:
        return f"{stem} [{', '.join(note_ids)}]{terminator}"
    return f"{stem} — {NO_EVIDENCE}{terminator}"


def _claims(raw: object) -> tuple[tuple[Claim, ...], tuple[str, ...]]:
    """Every well-formed claim, plus one issue per claim that is not."""
    if raw is None:
        return (), ()
    if not isinstance(raw, list):
        return (), ("Answer `claims` was not a list: it must be an array of claim objects.",)
    claims: list[Claim] = []
    issues: list[str] = []
    for index, item in enumerate(raw):
        claim, issue = _one_claim(item, index)
        if claim is not None:
            claims.append(claim)
        if issue:
            issues.append(issue)
    return tuple(claims), tuple(issues)


def _one_claim(item: object, index: int) -> tuple[Claim | None, str]:
    """One claim object → a claim, or the issue that stops it being one."""
    if not isinstance(item, dict):
        return None, f"Claim {index} was not an object: each claim needs text and note_ids."
    text = item.get("text")
    if not isinstance(text, str) or not text.strip():
        return None, f"Claim {index} has no text: a claim is a sentence plus its evidence."
    ids = item.get("note_ids", [])
    if not isinstance(ids, list) or any(not isinstance(i, str) for i in ids):
        return None, f"Claim {index} note_ids was not a list of note ids: use [] if none apply."
    grade = item.get("grade") if isinstance(item.get("grade"), str) else ""
    note_ids = tuple(i.strip() for i in ids if i.strip())
    claim = Claim(text=text.strip(), note_ids=note_ids, grade=(grade or "").strip())
    return _with_provable_grade(claim), ""


def _with_provable_grade(claim: Claim) -> Claim:
    """The claim carrying the grade its cited notes actually PROVE — never the model's.

    The declared grade used to be checked and an overclaim refused with a nudge
    (INTELLIGENCE section 5.6's hole, closed here). Measured 2026-09-16/20 on the owner's
    real data, that refusal was the commonest reason a turn was rewritten: 11 of 14
    off-arm fallbacks and two of three live turns spent one or two whole model calls
    on "declares Established but its weakest cited note is Probable". The declaration
    was always redundant — the manifest knows every cited note's grade, and
    ``validator._grade_floor`` computes the floor from the cited ids regardless — so the
    server now takes the provable grade and moves on. Nothing about calibration is lost:
    the WORDING gate still judges every rendered sentence's hedge against those same note
    grades, and an overstated sentence still fails there. What is gone is a second
    round-trip to make the model restate a number the server already had. The field
    stays in the answer shape as guidance: asking for it keeps the model looking at the
    grade while it writes. Silence (grade unchanged) when nothing gradeable is cited.
    """
    if not claim.note_ids:
        return claim
    provable = _provable_rank(claim.note_ids)
    if provable is None:
        return claim
    if claim.grade in GRADE_RANK and GRADE_RANK[claim.grade] <= provable:
        return claim
    return Claim(text=claim.text, note_ids=claim.note_ids, grade=_weakest_grade(claim.note_ids))


def _provable_rank(note_ids: tuple[str, ...]) -> int | None:
    """The strictest rank among the cited notes the manifest knows, or None if none."""
    ranks = [GRADE_RANK[grade] for grade in _known_grades(note_ids)]
    return min(ranks) if ranks else None


def _weakest_grade(note_ids: tuple[str, ...]) -> str:
    """The grade name behind :func:`_provable_rank` — what the nudge has to say out loud."""
    return min(_known_grades(note_ids), key=lambda g: GRADE_RANK[g])


def _known_grades(note_ids: tuple[str, ...]) -> list[str]:
    return [g for i in note_ids if (g := manifest.grade_of(i)) in GRADE_RANK]


def _opening_issues(opening: str) -> tuple[str, ...]:
    """The frame may DESCRIBE; it may not claim. That is what closes the hole.

    Without this the shape would be advisory: a model could put its whole answer in
    ``opening`` and the old free-text failure mode would return intact. The test applied
    is ``validator._sentence_issues``' own — ``calibration``'s interpretive vocabulary,
    with the same two exemptions (a reporting verb in a heading, a sentence quoting the
    owner's own measurement) — so a descriptive opening that names real numbers is legal
    and only an actual claim is redirected. Stricter than the validator on this field by
    design: there, an interpretive sentence needs a citation; here it needs to be a claim.
    """
    issues = []
    for unit in sentence_units(opening):
        if not INTERPRETIVE_RE.search(unit.text):
            continue
        if reports_only(unit.text) and (unit.heading or quotes_own_measurement(unit.text)):
            continue
        issues.append(
            f"Interpretive sentence in the opening: '{unit.text[:120]}' — the opening "
            "only reports numbers; move this into claims[] with the note_ids behind it."
        )
    return tuple(issues)


def _json_object(raw: str) -> dict | None:
    """The JSON object in a model turn, tolerating a code fence or a word of preamble.

    Tolerant on purpose and only here: JSON mode cannot be requested on a round that also
    offers tools (``coach._answer_format``), so the shape arrives by instruction on most
    turns. A fence or a "Here you go:" is a formatting slip, not an ungrounded answer, and
    refusing it would spend a retry proving the model can count backticks.
    """
    text = _FENCE_RE.sub("", raw or "").strip()
    start = text.find("{")
    if start < 0:
        return None
    end = _closing_brace(text, start)
    if end < 0:
        return None
    try:
        payload = json.loads(text[start : end + 1])
    except (json.JSONDecodeError, ValueError) as exc:
        log.warning("coach answer was not parseable JSON (%s) — nudging for the shape", exc)
        return None
    return payload if isinstance(payload, dict) else None


def _closing_brace(text: str, start: int) -> int:
    """Index of the brace closing the one at ``start``, or -1 — string-aware."""
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1
