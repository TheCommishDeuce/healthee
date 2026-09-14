"""Deterministic note chunker — the retrieval unit beneath a note.

``insights/manifest.py`` treats a note as one document; everything built on top of
it that needs to ask "does THIS text support THIS claim" (the support scorer in
``tests/grounding_eval/support.py``, and later retrieval) needs something smaller
than a 4.3k-44k-character note. A PASSAGE is that unit — one paragraph, one list
item, one table, one code block.

The split is deterministic and pure: same note body in, same passages out, no I/O
beyond ``manifest.prompt_body``. That matters because a passage's ``ref``
(``note_id#pN``) is meant to be a stable citation target: an eval record or a
retrieval index can point at one and expect it to still mean the same text
tomorrow, not whatever a re-run of a fuzzier splitter happened to produce.

## The rule, in one paragraph

A note's H2 sections (``## The evidence``, ``## Summary``, ...) each become zero
or more passages. Within a section, a fenced code block or a markdown table is one
passage, however long or short, never split and never merged: a formula missing
its closing fence or a table row with no header is nonsense, and a table that
already IS a complete unit is not "too short" the way a bare label is. A
sub-heading — an ATX ``### `` line, OR a column-zero line that is nothing but bold
text (the corpus's other spelling: ``injury_prevention``'s "**Training load — the
primary lever**" groups several bullets with no ``###`` at all) — is likewise its
own atomic passage: a mutation that folded one into the very NEXT block instead
would silently glue a group's label onto only its first bullet, leaving the label
absent from every other bullet in the group and making that one bullet stop
matching ``- **[Grade]...`` (measured: this fused 9 bullets across 5 real notes
before the fix). Everything else is prose: paragraphs break on a blank line —
including a BARE blockquote-marker line (``>`` with nothing after it), which is
markdown's paragraph break inside a quoted callout, not a line of prose, and
without this a multi-paragraph ``>``-quoted aside read as one unbroken block
several thousand characters long — except a top-level list item (``- ``, ``* ``,
``1. `` at column zero) which is its own passage including every indented
continuation line beneath it: this is what makes each ``## The evidence`` bullet
exactly one passage, since that section is nothing but top-level bullets. A blank
line followed by an INDENTED line does not end the list item (a bullet's own
worked sub-list — e.g. the ``< 5%`` / ``5-10%`` bands under a numbered item —
stays with it); a blank line followed by a dedented line does (the next bullet,
the next paragraph, or the next label).

A prose passage under 40 characters (a short fragment left over between two real
paragraphs) cannot carry a claim by itself, so it is folded into the passage that
follows it — or, if it is the very last passage in the document, into the one
before it. A table, fence or sub-heading may still SWALLOW a short fragment ahead
of it (a one-line caption belongs with the table it introduces) but is never
itself held back by this rule, whatever its own length.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from functools import lru_cache

from healthee.insights import manifest

# A real H2 heading only. `^##\s` would also eat `### ` sub-headings — see the
# module docstring on why those stay embedded in prose instead of splitting further.
_H2_RE = re.compile(r"^##[ \t]+(.*)$")
# An ATX sub-heading (H3+ — H2 is already gone by the time this runs). Corpus notes
# group `## The evidence` into `### Heat` / `### Altitude` sub-blocks; treating one as
# ordinary prose let it get folded FORWARD into the very next bullet by the short-label
# merge, which then no longer started with `- **[` — silently breaking "every evidence
# bullet is its own passage" wherever a note used sub-headings. Kept atomic instead:
# its own tiny passage, never merged into or swallowing a neighbour.
_ATX_RE = re.compile(r"^#{1,6}[ \t]+")
# A column-zero line that is ENTIRELY a bold span (`**Group label**`, optional
# trailing colon) — the corpus's other spelling of a sub-heading (e.g.
# `injury_prevention`'s "**Training load — the primary lever**" grouping several
# bullets, no `###`). Same shape `answer_text._BOLD_ONLY_RE` already treats as a
# label rather than a claim; redefined here (not imported) because this module has
# no use for `Unit`/`heading`-marking, only for "is this line a structural label".
# Column-zero only, like `_LIST_ITEM_RE` — an INDENTED all-bold line is a list
# item's own continuation text, not a section label, and must not end its block.
_BOLD_LABEL_RE = re.compile(r"^(\*\*|__)(?P<text>[^\s*_].*?)\1[ \t]*:?[ \t]*$")
# Column-zero only, like every other structural marker in this module — an INDENTED
# fence/table (several notes embed one inside a bullet's own worked explanation, e.g.
# `heart_rate_zones`' "5-zone model" bullet) is that bullet's continuation, not a
# section-level unit of its own. Pulling it out anyway used to tear one list item into
# three top-level passages (prose / table / prose) and left the table-and-fence
# fragments starting with the bullet's own indentation — an orphaned-looking passage
# for a reason, not a bug, until this was tightened to match the list-item convention.
_FENCE_RE = re.compile(r"^```")
_TABLE_ROW_RE = re.compile(r"^\|")
# A bare blockquote marker line (`>`, `> `, `>>`) carries no content of its own — it is
# markdown's paragraph-break INSIDE a quoted callout, not a line of prose. Treating only
# real blank lines as breaks left a multi-paragraph `>`-quoted aside (several corpus
# notes use these for "this used to be wrong, here is the correction" callouts) as one
# unbroken block of prose, since every line in it is technically non-blank — that is
# what produced multi-thousand-character passages the 2,500-char budget is meant to catch.
_BLOCKQUOTE_BLANK_RE = re.compile(r"^[ \t]*>+[ \t]*$")
# Column-zero only: a `-`/`*`/`1.` marker with LEADING whitespace is a nested
# sub-item, handled as a continuation line of its parent, never its own passage.
_LIST_ITEM_RE = re.compile(r"^(?:[-*]|\d+\.)\s+")
_MIN_PASSAGE_CHARS = 40


def _is_blank(line: str) -> bool:
    """True for an empty line OR a content-free blockquote marker line."""
    return not line.strip() or bool(_BLOCKQUOTE_BLANK_RE.match(line))


@dataclass(frozen=True)
class Passage:
    """One retrievable, citable unit of a note. See the module docstring for the split rule."""

    note_id: str
    index: int
    section: str
    text: str

    @property
    def ref(self) -> str:
        """The stable citation target ``passage()`` resolves back to this passage."""
        return f"{self.note_id}#p{self.index}"


@lru_cache(maxsize=256)
def passages(note_id: str) -> tuple[Passage, ...]:
    """Every passage of one note, in document order. ``()`` for an unknown id.

    ``manifest.prompt_body`` already degrades to ``""`` for an id it doesn't
    recognise rather than raising (its own docstring says so), so an unknown id
    is not a special case here: an empty body simply yields no blocks.
    """
    body = manifest.prompt_body(note_id)
    if not body:
        return ()
    blocks = _merge_short(_blocks(body))
    return tuple(
        Passage(note_id=note_id, index=i, section=section, text=text)
        for i, (section, text) in enumerate(blocks)
    )


@lru_cache(maxsize=1)
def all_passages() -> tuple[Passage, ...]:
    """Every passage of every citable note, in manifest order."""
    result: list[Passage] = []
    for note in manifest.all_notes():
        result.extend(passages(note.id))
    return tuple(result)


def passage(ref: str) -> Passage | None:
    """Resolve a ``note_id#pN`` ref back to its ``Passage``.

    ``None`` for anything that isn't that exact shape (no ``#p``, a non-numeric
    index, an id or index out of range) — a malformed or stale ref is a lookup
    miss here, never an exception a caller has to guard against.
    """
    note_id, sep, tail = ref.rpartition("#p")
    if not sep or not note_id or not tail.isdigit():
        return None
    note_passages = passages(note_id)
    index = int(tail)
    return note_passages[index] if 0 <= index < len(note_passages) else None


def _split_sections(body: str) -> list[tuple[str, str]]:
    """``(heading, section_text)`` in document order; ``""`` heading for any preamble."""
    sections: list[tuple[str, list[str]]] = [("", [])]
    for line in body.splitlines():
        heading = _H2_RE.match(line)
        if heading:
            sections.append((heading.group(1).strip(), []))
        else:
            sections[-1][1].append(line)
    return [
        (heading, "\n".join(lines))
        for heading, lines in sections
        if heading or any(line.strip() for line in lines)
    ]


def _starts_fence(line: str) -> bool:
    return bool(_FENCE_RE.match(line))


def _starts_table(line: str) -> bool:
    return bool(_TABLE_ROW_RE.match(line))


def _starts_heading(line: str) -> bool:
    return bool(_ATX_RE.match(line) or _BOLD_LABEL_RE.match(line))


def _consume_fence(lines: list[str], i: int) -> int:
    """End index (exclusive) of the fenced block opening at ``lines[i]``."""
    n = len(lines)
    j = i + 1
    while j < n and not _FENCE_RE.match(lines[j]):
        j += 1
    return min(j + 1, n)


def _consume_table(lines: list[str], i: int) -> int:
    """End index (exclusive) of the contiguous table-row run starting at ``lines[i]``."""
    n = len(lines)
    j = i
    while j < n and _TABLE_ROW_RE.match(lines[j]):
        j += 1
    return j


def _consume_heading(_lines: list[str], i: int) -> int:
    """A sub-heading is always exactly one line."""
    return i + 1


# The ONE source of truth for "what starts a boundary run, and how much of it to eat".
# `_is_boundary_start` is DERIVED from this table rather than kept as a second,
# hand-written list of the same three checks — because two lists that must agree is
# exactly how a real hang happened here in review: a mutation dropped one predicate
# from `_segments`' own dispatch while `_is_boundary_start` still reported that line as
# a boundary. The prose scan then stopped immediately in front of it, the dispatch loop
# found no consumer for it, fell through to "prose" again, and the inner scan stopped
# immediately again — zero lines consumed, `i` never advances, infinite loop. Caught in
# review only by a wall-clock timeout, not a red test, because nothing ever raised. With
# one shared table, removing an entry removes it from both the predicate and the
# dispatch in the same edit — the class of bug is structurally gone, not just re-tested.
_BOUNDARY_KINDS: tuple[tuple[str, Callable[[str], bool], Callable[[list[str], int], int]], ...] = (
    ("fence", _starts_fence, _consume_fence),
    ("table", _starts_table, _consume_table),
    ("heading", _starts_heading, _consume_heading),
)


def _is_boundary_start(line: str) -> bool:
    """A line that ends a prose run: a fence, a table row, or a sub-heading."""
    return any(starts(line) for _kind, starts, _consume in _BOUNDARY_KINDS)


def _segments(text: str) -> list[tuple[str, list[str], bool]]:
    """``(kind, lines, atomic)`` contiguous runs of one section, in order.

    "fence", "table" and "heading" runs are atomic (never split further, never
    merged into or swallowing a neighbour downstream); "prose" is handed to
    :func:`_split_prose`. Every branch below is guaranteed to consume at least one
    line — see :data:`_BOUNDARY_KINDS` for why that guarantee is load-bearing in a
    module that sits in production retrieval, not defensive decoration.
    """
    lines = text.splitlines()
    out: list[tuple[str, list[str], bool]] = []
    i, n = 0, len(lines)
    while i < n:
        for kind, starts, consume in _BOUNDARY_KINDS:
            if not starts(lines[i]):
                continue
            end = consume(lines, i)
            if end <= i:
                raise ValueError(
                    f"passages._segments: {kind!r} consumed no lines at {lines[i]!r} — "
                    "every _BOUNDARY_KINDS consumer must advance past its start line"
                )
            out.append((kind, lines[i:end], True))
            i = end
            break
        else:
            j = i
            while j < n and not _is_boundary_start(lines[j]):
                j += 1
            if j == i:
                # Only reachable if `_is_boundary_start` disagrees with
                # `_BOUNDARY_KINDS` — impossible in shipped code (one derives from
                # the other), so this can only fire under a test that deliberately
                # decouples them. A note that reaches this is not describable by
                # the current design; a loud failure beats a silent infinite loop
                # in a path that serves real requests.
                raise ValueError(
                    f"passages._segments: {lines[i]!r} is a boundary start with no "
                    "matching consumer in _BOUNDARY_KINDS"
                )
            out.append(("prose", lines[i:j], False))
            i = j
    return out


def _split_prose(lines: list[str]) -> list[str]:
    """Blank-line paragraphs, except a top-level list item stays one block with
    its indented continuation (see the module docstring for the lookahead rule).

    A bare blockquote-marker line counts as blank here too (:func:`_is_blank`) — a
    `>`-quoted callout's internal paragraph breaks are real breaks, not prose.
    """
    blocks: list[str] = []
    current: list[str] = []

    def flush() -> None:
        if current:
            blocks.append("\n".join(current))
            current.clear()

    n = len(lines)
    for i, line in enumerate(lines):
        if _LIST_ITEM_RE.match(line):
            flush()
            current.append(line)
        elif _is_blank(line):
            following = next((lines[j] for j in range(i + 1, n) if not _is_blank(lines[j])), None)
            if current and following is not None and following[:1] in (" ", "\t"):
                current.append(line)  # a bullet's own indented sub-list continues it
            else:
                flush()
        else:
            current.append(line)
    flush()
    return blocks


def _blocks(body: str) -> list[tuple[str, str, bool]]:
    """Every ``(section, text, atomic)`` block of a note body, before short-merging."""
    out: list[tuple[str, str, bool]] = []
    for section, section_text in _split_sections(body):
        for kind, lines, atomic in _segments(section_text):
            if kind == "prose":
                out.extend((section, t, False) for t in _split_prose(lines) if t.strip())
                continue
            joined = "\n".join(lines).strip("\n")
            if joined.strip():
                out.append((section, joined, atomic))
    return out


def _merge_short(blocks: list[tuple[str, str, bool]]) -> list[tuple[str, str]]:
    """Fold a prose passage under ``_MIN_PASSAGE_CHARS`` into the block after it.

    A table or fenced code block is never held back by this rule even when it is
    short by character count — it is already a complete unit by construction, and
    the "never split" guarantee applies both ways: a table is not something to
    glue onto its neighbour either. It can still SWALLOW a short label that
    precedes it (a one-line caption belongs with the table it introduces).
    """
    merged: list[tuple[str, str]] = []
    pending: str | None = None
    for section, text, atomic in blocks:
        if pending is not None:
            text = f"{pending}\n{text}"
            pending = None
        if not atomic and len(text) < _MIN_PASSAGE_CHARS:
            pending = text
            continue
        merged.append((section, text))
    if pending is not None:
        if merged:
            last_section, last_text = merged[-1]
            merged[-1] = (last_section, f"{last_text}\n{pending}")
        else:
            merged.append(("", pending))
    return merged
