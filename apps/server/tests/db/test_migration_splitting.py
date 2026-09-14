"""Every migration must survive the runner's statement splitter — checked, not assumed.

``db/migrate.py`` strips ``--`` comments and splits on ``;`` because psycopg3's
``execute()`` will not run multi-statement SQL. Its docstring states the price of that
simplicity: no ``;`` and no ``--`` inside a string literal. That was a documented
assumption with nothing enforcing it, and 0022 broke it with a ``COMMENT`` string that
said "PREMIUM_COACH_QUESTIONS; 0 is unlimited" — a statement cut in half at the semicolon,
which surfaced as a SyntaxError in every database test at once and named nothing about
the cause.

This reads the raw files with a small state machine instead of reusing the splitter,
because a check built on the thing it checks agrees with it by construction.
"""

from __future__ import annotations

from pathlib import Path

import pytest

_MIGRATIONS = Path(__file__).resolve().parents[2] / "src" / "healthee" / "db" / "migrations"


def _hazards(sql: str) -> list[str]:
    """Each ``;`` or ``--`` that sits INSIDE a single-quoted string, as ``line:col``.

    ``''`` inside a string is an escaped quote, which is two toggles that cancel — so a
    plain toggle on every ``'`` tracks the state correctly. Outside a string, ``--`` starts
    a comment to end of line, and quotes inside a comment do not open a string.
    """
    found: list[str] = []
    in_string = False
    for line_no, line in enumerate(sql.splitlines(), start=1):
        col = 0
        while col < len(line):
            ch = line[col]
            if not in_string and line.startswith("--", col):
                break
            if ch == "'":
                in_string = not in_string
            elif in_string and (ch == ";" or line.startswith("--", col)):
                found.append(f"{line_no}:{col + 1} {line.strip()[:60]!r}")
            col += 1
    return found


@pytest.mark.parametrize("path", sorted(_MIGRATIONS.glob("*.sql")), ids=lambda p: p.name)
def test_no_migration_hides_a_separator_inside_a_string(path: Path) -> None:
    hazards = _hazards(path.read_text())
    assert not hazards, (
        f"{path.name} has ';' or '--' inside a string literal, which migrate.py's splitter "
        f"cuts through: {hazards}"
    )


def test_the_guard_catches_the_bug_it_exists_for() -> None:
    """Proves the check can fail — against the exact string that broke 0022."""
    broken = "COMMENT ON COLUMN t.c IS\n  'defers to X; 0 is unlimited';\n"
    assert _hazards(broken), "the guard passed the very string that broke the runner"
    assert not _hazards("COMMENT ON COLUMN t.c IS 'owner''s cap, 0 is unlimited';\n")
    assert not _hazards("-- a comment; with a ' quote in it\nSELECT 1;\n")
