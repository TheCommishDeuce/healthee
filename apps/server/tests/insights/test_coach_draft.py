"""``coach_draft.draft_prose`` — the coach's answer as prose while still being written.

No DB, no network, no manifest: this module is a pure text scanner over the coach's
own JSON answer contract (``coach_answer.ANSWER_SHAPE``), so every test here is
arithmetic over strings. The two property tests are the point (module docstring's
"why the result only ever grows"); the rest pin the specific behaviours that
invariant depends on — the escape decoder, the citation format, and that garbage
input is just another kind of "nothing recognisable yet" rather than an exception.
"""

from __future__ import annotations

import json
import re

import pytest

from healthee.insights import coach_answer
from healthee.insights.coach_draft import draft_prose

# The citation suffix this module (and ``coach_answer._cite_sentence``) appends —
# " [id]" or " [id, id]" — immediately before a sentence's terminator. Stripping it is
# how the prefix property test states its invariant without caring WHEN a claim's
# ``note_ids`` array happened to close.
_CITATION_RE = re.compile(r" \[[a-z0-9_]+(?:, [a-z0-9_]+)*\]")


def _strip_citations(rendered: str) -> str:
    return _CITATION_RE.sub("", rendered)


def _payload(opening: str, claims: list[tuple[str, list[str], str]]) -> dict:
    return {
        "coach_answer": {
            "opening": opening,
            "claims": [{"text": t, "note_ids": ids, "grade": grade} for t, ids, grade in claims],
            "asserts": [],
        }
    }


# A real double quote and a real newline in the OPENING, so json.dumps must escape them
# (\" and \n) — exactly the escapes the decoder has to resolve rather than emit raw.
# `café` forces a non-ASCII character, which `json.dumps`'s default `ensure_ascii=True`
# writes as a `\u00e9` escape — the third escape family the decoder must resolve.
_OPENING = 'RHR read "54" last night.\nSteady as usual (café week aside).'

_CLAIM_ALL_CITED: list[tuple[str, list[str], str]] = [
    ("Regular movement supports recovery. It also helps sleep depth.", ["note_a"], ""),
    ("A single walk will not fix months of poor sleep.", ["note_b", "note_c"], ""),
]
FULL_ALL_CITED = json.dumps(_payload(_OPENING, _CLAIM_ALL_CITED))

_CLAIM_MIXED: list[tuple[str, list[str], str]] = [
    ("Regular movement supports recovery.", ["note_a"], ""),
    ("This part cites nothing.", [], ""),
]
FULL_MIXED = json.dumps(_payload(_OPENING, _CLAIM_MIXED))


# ── the two property tests ────────────────────────────────────────────────────────


def test_every_prefix_is_a_prefix_of_the_full_draft_once_citations_are_stripped() -> None:
    """THE invariant: for a fixed, complete answer, ``draft_prose`` of any prefix of its
    JSON — stripped of the citation brackets this module writes — is a literal string
    PREFIX of ``draft_prose`` of the full text, stripped the same way.

    The strip is the whole "modulo the citation suffix" clause: a claim's ``note_ids``
    array closes at one exact character position in the stream, and from that position
    on its bullet's TAIL is rewritten (the sentence's terminator stripped and
    re-attached after the bracket, exactly as ``coach_answer._cite_sentence`` does) —
    the one place this module's output is not a pure append. Stripping the bracket
    from both sides removes exactly that rewritten tail and nothing else, because the
    fixture's sentences are separated by single spaces (the same normalisation
    ``coach_answer.render`` itself performs), so nothing else about the growth is a
    rewrite.
    """
    full = FULL_ALL_CITED
    full_stripped = _strip_citations(draft_prose(full))
    for k in range(len(full) + 1):
        prefix_stripped = _strip_citations(draft_prose(full[:k]))
        assert full_stripped.startswith(prefix_stripped), (
            f"prefix length {k} ({full[:k]!r}) produced {prefix_stripped!r}, "
            f"not a prefix of {full_stripped!r}"
        )


def test_no_prefix_ever_emits_a_raw_backslash_escape_sequence() -> None:
    """Every escape family in the fixture (``\\"``, ``\\n``, ``\\u00e9``) must decode —
    never survive as literal backslash characters in the rendered draft, at ANY prefix
    length, including ones that cut an escape sequence in half."""
    full = FULL_ALL_CITED
    for k in range(len(full) + 1):
        rendered = draft_prose(full[:k])
        assert '\\"' not in rendered, f'prefix length {k} leaked a raw \\" into {rendered!r}'
        assert "\\n" not in rendered, f"prefix length {k} leaked a raw \\n into {rendered!r}"
        assert "\\u" not in rendered, f"prefix length {k} leaked a raw \\u escape into {rendered!r}"


# ── equivalence with the validated render ─────────────────────────────────────────


def test_a_complete_all_cited_answer_matches_the_validated_render_exactly() -> None:
    parsed, issues = coach_answer.parse(FULL_ALL_CITED)
    assert parsed is not None, issues
    assert draft_prose(FULL_ALL_CITED) == coach_answer.render(parsed)


def test_an_uncited_claim_differs_from_the_validated_render_only_by_the_escape_mark() -> None:
    parsed, issues = coach_answer.parse(FULL_MIXED)
    assert parsed is not None, issues
    validated = coach_answer.render(parsed)
    draft = draft_prose(FULL_MIXED)
    assert draft != validated
    assert draft == validated.replace(f" — {coach_answer.NO_EVIDENCE}", "")


# ── the specific behaviours the invariant depends on ──────────────────────────────


def test_a_half_written_opening_renders_as_the_half_sentence() -> None:
    partial = '{"coach_answer": {"opening": "Your RHR was ste'
    assert draft_prose(partial) == "Your RHR was ste"


def test_everything_before_the_openings_first_quote_is_empty() -> None:
    assert draft_prose('{"coach_answer": {"opening"') == ""
    assert draft_prose('{"coach_answer": {"opening":   ') == ""


def test_a_claims_citation_appears_only_once_its_note_ids_array_closes() -> None:
    base = '{"coach_answer": {"opening": "", "claims": [{"text": "Sleep well tonight."'
    not_yet = base + ', "note_ids": ["note_a"'
    closed = base + ', "note_ids": ["note_a"]'
    assert draft_prose(not_yet) == "- Sleep well tonight."
    assert draft_prose(closed) == "- Sleep well tonight [note_a]."


def test_a_closed_but_empty_note_ids_array_earns_no_citation_and_no_escape_mark() -> None:
    text = '{"coach_answer": {"opening": "", "claims": [{"text": "Just reporting.", "note_ids": []'
    assert draft_prose(text) == "- Just reporting."


def test_a_rewrite_a_new_claim_starts_a_fresh_bullet_from_empty() -> None:
    """Two claims in the SAME text: the second's bullet appears only once its own
    ``"text"`` key has been seen — nothing here waits on the first claim to close."""
    one = '{"coach_answer": {"opening": "", "claims": [{"text": "First."}, {"text": "Sec'
    assert draft_prose(one) == "- First.\n- Sec"


def test_an_inline_personal_finding_tag_stays_but_a_bracket_id_convention_is_stripped() -> None:
    text = json.dumps(
        _payload(
            "",
            [
                (
                    "Mood dipped yesterday, matching a pattern here [personal_finding:mood_dip].",
                    ["note_a"],
                    "",
                ),
                ("Written the old way [note_a].", ["note_a"], ""),
            ],
        )
    )
    rendered = draft_prose(text)
    assert "[personal_finding:mood_dip]" in rendered
    assert "[note_a] [note_a]" not in rendered  # the inline convention is stripped, not doubled
    assert rendered.count("[note_a]") == 2  # one real citation per claim, nothing extra


# ── garbage never raises ──────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "garbage",
    [
        "",
        "{",
        "not json at all {{{",
        '{"coach_answer"',
        '{"coach_answer": {"claims": [{"note_ids": [1, 2, "x"',
        '{"coach_answer": {"opening": "unterminated \\\\',
        '{"coach_answer": {"opening": "bad unicode \\u00',
        "\x00\x01 binary-ish ﻿",
        '{"coach_answer": {"claims": [{"text": "a", "note_ids": [}]',
        '"opening": "text": "note_ids":',
    ],
)
def test_garbage_input_never_raises(garbage: str) -> None:
    assert isinstance(draft_prose(garbage), str)
