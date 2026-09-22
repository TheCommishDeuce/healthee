"""Migration runner — applies pending `migrations/*.sql` transactionally.

Each numbered SQL file is applied in its own transaction and recorded in
`schema_migrations`; already-recorded files are skipped, so running twice is a
no-op. The migrations themselves are idempotent (IF NOT EXISTS / if_not_exists),
which keeps a half-applied file safe to replay.

Run it as a module against a configured database:

    uv run python -m healthee.db.migrate

Or ask it whether applying anything is NEEDED, changing nothing:

    uv run python -m healthee.db.migrate --check   # exit 0 clean, 1 if pending

`--check` is the deploy preflight (`infra/dockge/compose.yaml`). It exists because
Dockge's update control is `docker compose pull` + `up -d` and nothing more, which
swaps the image without ever running this module — and our migrations are NOT
backwards-compatible (0004 folds `user_id` into the natural keys, 0007 drops a
DEFAULT), so the new image against the old schema is a broken deployment rather than
a degraded one. Run on the NEW image before anything is recreated, a non-zero exit
refuses the swap and names what is pending.

It validates the CONFIG as a side effect, and that is the second half of its job
rather than an accident: `admin_connection()` calls `get_settings()`, so a release
that adds a required var — or one where `OPENROUTER_API_KEY` is set with a blank
model id — raises here, on the new image, instead of in a container that has already
replaced the working one.

It connects as the OWNER/ADMIN role (`core.db.admin_connection`), not the app pool:
migrations are DDL, and the least-privilege app role deliberately has no CREATE or
ALTER (Phase 6.5b-1, MULTI_USER.md §3.3).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import LiteralString, cast

from healthee.core.db import admin_connection
from healthee.core.logging import configure_logging, get_logger

log = get_logger(__name__)

_MIGRATIONS_DIR = Path(__file__).parent / "migrations"

_CREATE_LEDGER = """
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     TEXT        PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


_LINE_COMMENT_RE = re.compile(r"--[^\n]*")


def _split_statements(sql: str) -> list[str]:
    """Split a migration file into individual statements.

    psycopg3's `execute()` runs one statement at a time, so migrations are
    applied statement-by-statement (repo rule in CLAUDE.md). Line comments are
    stripped first because they can contain ';'. This simple splitter assumes
    migrations contain no ';' or '--' inside string literals or function bodies —
    true for our DDL (plain CREATE/ALTER, no DO blocks).
    """
    stripped = _LINE_COMMENT_RE.sub("", sql)
    return [stmt.strip() for stmt in stripped.split(";") if stmt.strip()]


def _migration_files() -> list[Path]:
    """All migration files, ordered by their numeric filename prefix."""
    return sorted(_MIGRATIONS_DIR.glob("*.sql"))


def _applied_versions() -> set[str]:
    """Versions already recorded in schema_migrations (creating it if absent)."""
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(_CREATE_LEDGER)
        cur.execute("SELECT version FROM schema_migrations")
        return {row[0] for row in cur.fetchall()}


def pending_migrations() -> list[Path]:
    """Migration files not yet recorded as applied, in order."""
    applied = _applied_versions()
    return [path for path in _migration_files() if path.stem not in applied]


def _apply_one(path: Path) -> None:
    """Apply a single migration file and record it — one transaction.

    Each statement runs on its own `execute()` (psycopg3 does not run
    multi-statement SQL); the recording INSERT shares the transaction, so any
    failure rolls back the whole file.
    """
    statements = _split_statements(path.read_text())
    with admin_connection() as conn, conn.cursor() as cur:
        for statement in statements:
            # Trusted SQL — from committed migration files, never user input.
            cur.execute(cast("LiteralString", statement))
        cur.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.stem,))


def apply_migrations() -> list[str]:
    """Apply every pending migration in order. Returns the versions applied."""
    pending = pending_migrations()
    if not pending:
        log.info("no pending migrations")
        return []
    applied: list[str] = []
    for path in pending:
        _apply_one(path)
        applied.append(path.stem)
        log.info("applied migration %s", path.stem)
    return applied


def _check() -> None:
    """Report whether migrations are pending; exit non-zero when they are.

    Non-zero is the whole point: this runs as a compose dependency
    (`condition: service_completed_successfully`), so the exit status is what
    refuses to recreate the app containers. The pending versions are logged by
    name because the operator's next step is to run the real deploy, and a
    refusal that does not say what it is refusing over is just an outage.
    """
    pending = [path.stem for path in pending_migrations()]
    if not pending:
        log.info("preflight OK — schema is current, no migrations pending")
        return
    log.error(
        "preflight FAILED — %d migration(s) pending: %s. This release changes the "
        "schema, and old code cannot serve the new one, so it is not a pull-and-restart. "
        "Run the real deploy (backup -> stop -> migrate -> start): infra/deploy.sh",
        len(pending),
        ", ".join(pending),
    )
    raise SystemExit(1)


def main() -> None:
    """CLI entry point: configure logging, then apply pending migrations.

    `--check` reports instead of applying — see the module docstring.
    """
    configure_logging()
    if "--check" in sys.argv[1:]:
        _check()
        return
    applied = apply_migrations()
    log.info("migrations complete (%d applied)", len(applied))


if __name__ == "__main__":
    main()
