"""The coach's answer as PROSE while it is still being written (the owner's 2026-09-19
call — "make it feel like claude — stream it as it starts and swap", docs/INTELLIGENCE.md
section 3). A DRAFT is shown as a draft; the validated answer supersedes it. Nothing here
validates, cites, or ships — see ``coach_loop.ToolLoop`` for how the draft is throttled
into progress events, and ``pipeline.py``/``coach_answer.py`` for the gates the final
answer still faces unchanged.

## Why this cannot be ``json.loads``

The model writes ``coach_answer.ANSWER_SHAPE`` a token at a time, so every prefix the
transport hands us is (almost always) syntactically INVALID JSON — a string cut off
mid-sentence, an array missing its closing bracket. :func:`draft_prose` is a tolerant,
hand-rolled scanner that reads whatever has arrived and renders it the way
``coach_answer.render`` would once it is complete: it never raises, and a half-written
sentence renders as exactly that half sentence.

## What it extracts, and in what order

Walking the raw text left to right, it takes the FIRST ``"opening"`` string value (open
or closed), then each claim's ``"text"`` string value in the order they appear, and
attaches that claim's ``note_ids`` — mirroring ``coach_answer._cited``'s own citation
placement exactly — only once that claim's ``note_ids`` ARRAY HAS CLOSED (the closing
``]`` has arrived) and is non-empty. A claim whose array has not closed yet renders its
text bare; the honest-escape mark (``coach_answer.NO_EVIDENCE``) is never attached here
— an uncited claim might still be mid-stream, and marking it unsupported is the
VALIDATED render's business, not a draft's guess.

## Why the result only ever grows

Every string is decoded strictly left to right and every decoded character is APPENDED,
never revised — so for two prefixes of the same underlying text, the shorter one's
decode is always a literal prefix of the longer one's, up to whichever claim's citation
state flips from "not yet cited" to "cited" in between them (the one place the tail of
an already-rendered bullet is rewritten, by design: the sentence's terminator is
stripped and re-attached after the bracket, exactly as ``coach_answer._cite_sentence``
does for the final render). ``tests/insights/test_coach_draft.py`` states the exact
invariant and checks every prefix length of a fixed answer against it.
"""

from __future__ import annotations

import re

from healthee.insights.coach_answer import _NOTE_BRACKET_RE, _SENTENCE_SPLIT_RE, _cite_sentence

# The three fields a draft ever reads off the model's partial JSON — see the module
# docstring for why no other key (``claims``, ``grade``, ``asserts``, the envelope key
# itself) needs to be recognised: the scanner jumps straight from one of these three to
# the next, and everything in between is skipped without being parsed at all.
_KEY_RE = re.compile(r'"(opening|text|note_ids)"\s*:\s*')

_ESCAPES = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}

_WHITESPACE = " \t\r\n"


def draft_prose(partial: str) -> str:
    """The owner-facing prose for whatever of one coach answer has arrived so far.

    Never raises: a scan that finds nothing recognisable renders as ``""``, the same
    empty state a stream has before its first token.
    """
    opening, claims = _scan(partial)
    lines = [opening] if opening else []
    bullets = [f"- {_claim_prose(claim)}" for claim in claims if claim["text"].strip()]
    if bullets:
        lines.append("\n".join(bullets))
    return "\n\n".join(lines)


def _scan(text: str) -> tuple[str, list[dict]]:
    """One left-to-right pass extracting ``opening`` and every claim found after it.

    ``cursor`` only ever moves forward — past a decoded string's end, past a decoded
    array's end, or past one key match when its value is not the shape expected (garbage
    input, or a value that has not started yet) — so this always terminates.
    """
    opening = ""
    opening_seen = False
    claims: list[dict] = []
    current: dict | None = None
    cursor = 0
    while (match := _KEY_RE.search(text, cursor)) is not None:
        key = match.group(1)
        pos = _skip_ws(text, match.end())
        if key in ("opening", "text"):
            if pos >= len(text) or text[pos] != '"':
                cursor = match.end()
                continue
            value, end, _closed = _decode_string(text, pos + 1)
            if key == "opening" and not opening_seen:
                opening, opening_seen = value, True
            elif key == "text":
                current = {"text": value, "note_ids": None}
                claims.append(current)
            cursor = end
        else:  # "note_ids"
            if pos >= len(text) or text[pos] != "[":
                cursor = match.end()
                continue
            ids, end, closed = _decode_string_array(text, pos + 1)
            if current is not None and closed:
                current["note_ids"] = tuple(ids)
            cursor = end
    return opening, claims


def _claim_prose(claim: dict) -> str:
    """One claim's line — cited exactly as ``coach_answer._cited`` would, or bare.

    ``note_ids`` is ``None`` (array not yet closed) or ``()`` (closed, empty): neither
    earns a citation, and unlike the validated render neither earns the honest-escape
    mark — see the module docstring for why that mark is not this module's to write.
    """
    body = _NOTE_BRACKET_RE.sub("", claim["text"]).strip()
    note_ids = claim["note_ids"]
    if not note_ids:
        return body
    parts = [p for p in _SENTENCE_SPLIT_RE.split(body) if p.strip()]
    return " ".join(_cite_sentence(part, note_ids) for part in parts or [body])


def _skip_ws(text: str, i: int) -> int:
    n = len(text)
    while i < n and text[i] in _WHITESPACE:
        i += 1
    return i


def _decode_string(text: str, i: int) -> tuple[str, int, bool]:
    """Decode a JSON string starting right after its opening quote.

    Returns ``(value, index_after_the_consumed_text, closed)``. Stops cleanly at a
    dangling escape — a trailing backslash, or a ``\\u`` with fewer than four hex digits
    left in ``text`` — rather than ever emitting a raw backslash sequence: the partial
    text simply has not delivered the rest of that escape yet.
    """
    out: list[str] = []
    n = len(text)
    while i < n:
        char = text[i]
        if char == '"':
            return "".join(out), i + 1, True
        if char != "\\":
            out.append(char)
            i += 1
            continue
        if i + 1 >= n:
            break  # dangling backslash — wait for more text
        escape = text[i + 1]
        if escape == "u":
            if i + 6 > n:
                break  # incomplete \uXXXX
            try:
                out.append(chr(int(text[i + 2 : i + 6], 16)))
            except ValueError:
                break
            i += 6
            continue
        mapped = _ESCAPES.get(escape)
        i += 2
        if mapped is not None:
            out.append(mapped)
    return "".join(out), n, False


def _decode_string_array(text: str, i: int) -> tuple[list[str], int, bool]:
    """Decode a JSON array of strings starting right after its opening ``[``.

    Returns ``(items, index_after_the_consumed_text, closed)``; a string still being
    written when the array's own end is reached is dropped rather than half-included —
    only a CLOSED array is ever attached to a claim (module docstring), so a dropped
    trailing item changes nothing a caller reads.
    """
    items: list[str] = []
    n = len(text)
    i = _skip_ws(text, i)
    while i < n:
        if text[i] == "]":
            return items, i + 1, True
        if text[i] != '"':
            i += 1  # a comma, or garbage — skip one char rather than loop forever
            i = _skip_ws(text, i)
            continue
        value, end, closed = _decode_string(text, i + 1)
        if not closed:
            return items, end, False
        items.append(value)
        i = _skip_ws(text, end)
    return items, n, False
