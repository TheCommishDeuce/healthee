"""``insights/passages.py`` — the note chunker, on a synthetic fixture and the real corpus.

The synthetic fixture pins the split RULES (H2 boundaries, paragraph vs. list-item vs.
table vs. fence, the short-label merge, deterministic indices, ``ref`` round-tripping)
against exact expected text, so a mutation to any one rule fails a specific assertion
rather than a vague "some passage looked wrong". The real-corpus tests then pin the
INVARIANTS the production data must keep holding as the corpus grows.
"""

from __future__ import annotations

import re
from collections.abc import Iterator

import pytest

from healthee.insights import manifest, passages

_FIXTURE_ID = "test_fixture_note"

_FIXTURE = """\
# Test Note

## Summary
See details below.

This is a full paragraph with enough characters to stand on its own as a
passage, proving blank-line paragraphs split correctly on their own.

## The evidence

- **[Established]** This is a multi-line bullet claim that spans
  two source lines and must be kept as ONE passage since it is a single
  top-level list item with indented continuation lines.

- **[Probable]** This is a second, separate bullet, split from the first
  by a blank line, and it must land in its own passage entirely.

## Grouped evidence

**Group Alpha**
- **[Established]** First bullet of group alpha, kept separate from its
  own label above even though there is no blank line between them.
- **[Probable]** Second bullet of group alpha, immediately following the
  first with no blank line, must still land in its own passage too.

**Group Beta**
- **[Contested]** Solo bullet under the second label in this section.

## How we compute it

```
CODE LINE ONE stays with

CODE LINE TWO even across the blank line above, because a fence is atomic
```

## Worked example

1. **First item, with a worked sub-list.** Intro text for the first numbered
   item, ending with a colon:

   - Indented sub-point one, part of item one.
   - Indented sub-point two, also part of item one.

2. **Second item.** A separate top-level item, dedented back to column zero.

## Data table

| A | B |
|---|---|
| 1 | 2 |

## A quoted correction

> **First quoted paragraph, checked 2026-08-01.** This callout opens with
> its own paragraph of quoted prose that must become its own passage.
>
> **Second quoted paragraph.** A bare `>` marker line above separates this
> from the first paragraph even though neither line is truly blank.
"""


@pytest.fixture(autouse=True)
def _fixture_note(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Swap in the synthetic note for `_FIXTURE_ID`; every other id passes through."""
    real_prompt_body = manifest.prompt_body

    def fake_prompt_body(note_id: str) -> str:
        if note_id == _FIXTURE_ID:
            return _FIXTURE
        return real_prompt_body(note_id)

    monkeypatch.setattr(manifest, "prompt_body", fake_prompt_body)
    passages.passages.cache_clear()
    passages.all_passages.cache_clear()
    yield
    passages.passages.cache_clear()
    passages.all_passages.cache_clear()


def _ps() -> tuple[passages.Passage, ...]:
    return passages.passages(_FIXTURE_ID)


# ── Synthetic fixture: the split rules ───────────────────────────────────────


def test_h2_sections_are_recorded_per_passage() -> None:
    sections = {p.section for p in _ps()}
    assert sections == {
        "",  # the H1 preamble line, its own atomic heading passage
        "Summary",
        "The evidence",
        "Grouped evidence",
        "Worked example",
        "How we compute it",
        "Data table",
        "A quoted correction",
    }


def test_h1_preamble_is_its_own_atomic_heading_passage() -> None:
    preamble = [p for p in _ps() if p.section == ""]
    assert len(preamble) == 1
    assert preamble[0].text == "# Test Note"
    assert preamble[0].index == 0


def test_short_plain_fragment_merges_into_the_paragraph_that_follows() -> None:
    """ "See details below." (19 chars) must not survive as its own passage — a
    mutation that dropped the merge step would produce a 2nd, tiny Summary passage
    instead of the single one asserted here."""
    summary = [p for p in _ps() if p.section == "Summary"]
    assert len(summary) == 1
    assert summary[0].text == (
        "See details below.\n"
        "This is a full paragraph with enough characters to stand on its own as a\n"
        "passage, proving blank-line paragraphs split correctly on their own."
    )


def test_bold_only_group_label_is_atomic_not_glued_to_its_first_bullet() -> None:
    """Real notes group bullets under a bold-only label with no blank line before
    bullet 1 — treating the label as ordinary prose would fold it into bullet 1
    only, leaving that one not starting with `- **[` and the rest unlabelled."""
    grouped = [p for p in _ps() if p.section == "Grouped evidence"]
    texts = [p.text for p in grouped]
    assert texts == [
        "**Group Alpha**",
        "- **[Established]** First bullet of group alpha, kept separate from its\n"
        "  own label above even though there is no blank line between them.",
        "- **[Probable]** Second bullet of group alpha, immediately following the\n"
        "  first with no blank line, must still land in its own passage too.",
        "**Group Beta**",
        "- **[Contested]** Solo bullet under the second label in this section.",
    ]


def test_numbered_item_keeps_its_indented_sub_list_across_a_blank_line() -> None:
    """P1: a numbered item's worked sub-list sits behind a blank line, indented.
    An unconditional `flush()` in place of the lookahead passed every prior test
    (none had a blank line INSIDE a list item) — this fixture does, so that
    mutation now tears the item into extra fragments instead of these two."""
    worked = [p for p in _ps() if p.section == "Worked example"]
    assert len(worked) == 2
    assert worked[0].text == (
        "1. **First item, with a worked sub-list.** Intro text for the first numbered\n"
        "   item, ending with a colon:\n"
        "\n"
        "   - Indented sub-point one, part of item one.\n"
        "   - Indented sub-point two, also part of item one."
    )
    assert worked[1].text == (
        "2. **Second item.** A separate top-level item, dedented back to column zero."
    )


def test_blockquote_callout_splits_on_its_own_bare_marker_lines() -> None:
    """A bare `>` line (no content) is markdown's paragraph break inside a quoted
    callout — a mutation that only recognised truly empty lines as blank would fuse
    both quoted paragraphs into one oversized passage instead of these two."""
    quoted = [p for p in _ps() if p.section == "A quoted correction"]
    assert len(quoted) == 2
    assert quoted[0].text.startswith("> **First quoted paragraph")
    assert quoted[1].text.startswith("> **Second quoted paragraph")


def test_evidence_bullets_are_two_separate_whole_passages() -> None:
    """Each bullet is multi-line in the source; a mutation that removed continuation
    handling would tear "two source lines" or "by a blank line" off its own claim."""
    evidence = [p for p in _ps() if p.section == "The evidence"]
    assert len(evidence) == 2
    assert evidence[0].text == (
        "- **[Established]** This is a multi-line bullet claim that spans\n"
        "  two source lines and must be kept as ONE passage since it is a single\n"
        "  top-level list item with indented continuation lines."
    )
    assert evidence[1].text == (
        "- **[Probable]** This is a second, separate bullet, split from the first\n"
        "  by a blank line, and it must land in its own passage entirely."
    )


def test_code_fence_survives_as_one_passage_despite_its_internal_blank_line() -> None:
    fence = [p for p in _ps() if p.section == "How we compute it"]
    assert len(fence) == 1
    assert fence[0].text.startswith("```")
    assert fence[0].text.endswith("```")
    assert "CODE LINE ONE" in fence[0].text
    assert "CODE LINE TWO" in fence[0].text


def test_table_survives_as_one_passage_even_though_it_is_short() -> None:
    """The table is 29 characters — under the 40-char merge floor — and must NOT be
    folded into its neighbour: a mutation that merged atomic blocks by length would
    fuse this into the preceding fence passage instead of keeping it separate."""
    table = [p for p in _ps() if p.section == "Data table"]
    assert len(table) == 1
    assert table[0].text == "| A | B |\n|---|---|\n| 1 | 2 |"


def test_indices_are_zero_based_and_sequential() -> None:
    ps = _ps()
    assert [p.index for p in ps] == list(range(len(ps)))


def test_ref_round_trips_through_passage() -> None:
    for p in _ps():
        assert p.ref == f"{_FIXTURE_ID}#p{p.index}"
        assert passages.passage(p.ref) == p


def test_nothing_from_the_body_is_silently_dropped() -> None:
    """Every distinctive phrase written into the fixture must land in SOME passage."""
    joined = "\n".join(p.text for p in _ps())
    for phrase in (
        "Test Note",
        "See details below.",
        "full paragraph",
        "multi-line bullet claim",
        "second, separate bullet",
        "Group Alpha",
        "Group Beta",
        "Solo bullet under the second label",
        "Indented sub-point one",
        "Indented sub-point two",
        "A separate top-level item",
        "CODE LINE ONE",
        "CODE LINE TWO",
        "| 1 | 2 |",
        "First quoted paragraph",
        "Second quoted paragraph",
    ):
        assert phrase in joined, phrase


# ── Malformed refs and unknown ids ────────────────────────────────────────────


def test_unknown_note_id_yields_no_passages() -> None:
    assert passages.passages("no_such_note_id_at_all") == ()


@pytest.mark.parametrize(
    "ref",
    [
        "not-a-ref-at-all",
        f"{_FIXTURE_ID}#pnotanumber",
        f"{_FIXTURE_ID}#p999",
        "#p0",
        "",
    ],
)
def test_malformed_or_out_of_range_ref_resolves_to_none(ref: str) -> None:
    assert passages.passage(ref) is None


# ── The progress guarantee (P6, mutation review) ──────────────────────────────


def test_a_boundary_start_with_no_consumer_raises_instead_of_hanging(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A real mutation dropped one `_BOUNDARY_KINDS` predicate from `_segments`'
    dispatch while `_is_boundary_start` (then a hand-written twin list) still
    matched the line — zero lines consumed, infinite loop, caught only by a 180s
    timeout, not a red test. The two are now one shared table, so this recreates
    the drift by patching `_is_boundary_start` directly and asserts a raise."""
    real_is_boundary_start = passages._is_boundary_start

    def fake_is_boundary_start(line: str) -> bool:
        return real_is_boundary_start(line) or line.startswith("~~~")

    monkeypatch.setattr(passages, "_is_boundary_start", fake_is_boundary_start)
    body = (
        "plain prose line one\n"
        "~~~ a marker no _BOUNDARY_KINDS consumer matches\n"
        "plain prose line two\n"
    )
    monkeypatch.setattr(
        manifest, "prompt_body", lambda note_id: body if note_id == "hang_note" else ""
    )
    passages.passages.cache_clear()
    with pytest.raises(ValueError, match="no matching consumer"):
        passages.passages("hang_note")


# ── Real corpus invariants ─────────────────────────────────────────────────


def _real_notes() -> tuple[manifest.ManifestNote, ...]:
    return manifest.all_notes()


def test_every_real_note_yields_at_least_three_passages() -> None:
    offenders = [n.id for n in _real_notes() if len(passages.passages(n.id)) < 3]
    assert offenders == [], offenders


def test_no_real_passage_begins_with_whitespace() -> None:
    """P1: an indented FIRST line can only be an orphaned continuation — every
    top-level unit starts flush at column zero by convention. Caught a real bug:
    an indented table inside a bullet (`heart_rate_zones`'s "5-zone model") used
    to get torn out as its own fragment before column-zero-only was enforced."""
    offenders = [p.ref for p in passages.all_passages() if p.text[:1].isspace()]
    assert offenders == [], f"passages beginning with whitespace: {offenders}"


_TABLE_OR_FENCE_RE = re.compile(r"^\s*(```|\|)")
# One documented exception (brief's own escape hatch: "assert with a reason").
# `weight_bmi_body_composition`'s "Stale weight is no longer used..." bullet is a
# single top-level list item — the chunker's own core rule says that MUST stay one
# passage — whose correction footnote is one continuous quoted paragraph with no
# internal blank line to split on: 2,771 characters of one coherent claim, not a
# chunking bug. Named explicitly rather than pattern-matched, so a genuinely NEW
# oversized passage still fails this test.
_KNOWN_OVERSIZE_REFS = frozenset({"weight_bmi_body_composition#p51"})


def test_no_real_passage_exceeds_2500_chars_except_tables_and_fences() -> None:
    offenders = [
        p.ref
        for p in passages.all_passages()
        if len(p.text) > 2500
        and not _TABLE_OR_FENCE_RE.match(p.text)
        and p.ref not in _KNOWN_OVERSIZE_REFS
    ]
    assert offenders == [], f"oversized non-table/fence passages: {offenders}"


_EVIDENCE_SECTION_RE = re.compile(r"^## The evidence\s*\n(.*?)(?=^##\s|\Z)", re.M | re.S)
_EVIDENCE_BULLET_START_RE = re.compile(r"^- \*\*\[", re.M)


def test_every_evidence_bullet_is_its_own_passage() -> None:
    """Cross-checks the raw `- **[Grade]` bullet count against passages actually
    produced for `## The evidence`, per note — a mutation that dropped continuation
    handling would silently fuse or fragment these."""
    mismatches = []
    for note in _real_notes():
        body = manifest.prompt_body(note.id)
        match = _EVIDENCE_SECTION_RE.search(body)
        if not match:
            continue
        raw_count = len(_EVIDENCE_BULLET_START_RE.findall(match.group(1)))
        got = [
            p
            for p in passages.passages(note.id)
            if p.section == "The evidence" and p.text.startswith("- **[")
        ]
        if len(got) != raw_count:
            mismatches.append((note.id, raw_count, len(got)))
    assert mismatches == [], mismatches


def test_no_line_of_a_real_note_is_silently_dropped() -> None:
    """Every non-blank, non-H2-heading line of the prompt body must appear (as a
    stripped substring) somewhere in the concatenation of that note's passages."""
    missing: list[tuple[str, str]] = []
    for note in _real_notes():
        body = manifest.prompt_body(note.id)
        joined = "\n".join(p.text for p in passages.passages(note.id))
        for line in body.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("## "):
                continue
            if stripped not in joined:
                missing.append((note.id, stripped))
    assert missing == [], missing[:10]
