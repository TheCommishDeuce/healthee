"""Unit tests for the migration runner's logic — file discovery, pending
selection, and recording — with the DB faked. The real apply against
TimescaleDB is covered by the integration test.
"""

from __future__ import annotations

import sys
from collections.abc import Iterator
from contextlib import contextmanager

import pytest

from healthee.db import migrate


def test_split_statements_strips_comments_and_splits_on_semicolons() -> None:
    sql = (
        "CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- note; with a semicolon\n"
        "CREATE TABLE t (id INT);\n"
    )
    stmts = migrate._split_statements(sql)
    assert stmts == ["CREATE EXTENSION IF NOT EXISTS pgcrypto", "CREATE TABLE t (id INT)"]


def test_baseline_migration_splits_into_many_statements() -> None:
    baseline = next(p for p in migrate._migration_files() if p.stem == "0001_initial")
    stmts = migrate._split_statements(baseline.read_text())
    # Extensions + create_hypertable + the tables/indexes — well over a dozen.
    assert len(stmts) > 15
    assert any(s.startswith("CREATE TABLE IF NOT EXISTS sample") for s in stmts)


def test_migration_files_are_sorted_and_include_baseline() -> None:
    files = migrate._migration_files()
    stems = [p.stem for p in files]
    assert "0001_initial" in stems
    assert stems == sorted(stems)


def test_pending_excludes_already_applied(monkeypatch: pytest.MonkeyPatch) -> None:
    # An applied version is dropped from pending; other numbered migrations remain.
    monkeypatch.setattr(migrate, "_applied_versions", lambda: {"0001_initial"})
    pending = [p.stem for p in migrate.pending_migrations()]
    assert "0001_initial" not in pending


def test_pending_empty_when_all_applied(monkeypatch: pytest.MonkeyPatch) -> None:
    applied = {p.stem for p in migrate._migration_files()}
    monkeypatch.setattr(migrate, "_applied_versions", lambda: applied)
    assert migrate.pending_migrations() == []


def test_pending_includes_unapplied(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(migrate, "_applied_versions", set)
    pending = [p.stem for p in migrate.pending_migrations()]
    assert "0001_initial" in pending


def test_apply_migrations_no_op_when_nothing_pending(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(migrate, "pending_migrations", list)
    assert migrate.apply_migrations() == []


class _RecordingCursor:
    def __init__(self, calls: list[tuple[str, object]]) -> None:
        self._calls = calls

    def execute(self, sql: str, params: object = None) -> None:
        self._calls.append((sql, params))

    def __enter__(self) -> _RecordingCursor:
        return self

    def __exit__(self, *_exc: object) -> bool:
        return False


class _RecordingConn:
    def __init__(self, cursor: _RecordingCursor) -> None:
        self._cursor = cursor

    def cursor(self) -> _RecordingCursor:
        return self._cursor

    def __enter__(self) -> _RecordingConn:
        return self

    def __exit__(self, *_exc: object) -> bool:
        return False


def test_apply_records_each_migration_version(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[str, object]] = []

    @contextmanager
    def _fake_admin_connection() -> Iterator[_RecordingConn]:
        yield _RecordingConn(_RecordingCursor(calls))

    monkeypatch.setattr(migrate, "admin_connection", _fake_admin_connection)
    baseline = next(p for p in migrate._migration_files() if p.stem == "0001_initial")
    monkeypatch.setattr(migrate, "pending_migrations", lambda: [baseline])

    applied = migrate.apply_migrations()

    assert applied == ["0001_initial"]
    # The DDL ran, then the version was recorded in the same transaction.
    assert any("INSERT INTO schema_migrations" in sql for sql, _ in calls)
    assert ("INSERT INTO schema_migrations (version) VALUES (%s)", ("0001_initial",)) in calls


# ── `--check`: the deploy preflight ─────────────────────────────────────────
#
# This is what stands between Dockge's "update" button (`compose pull` + `up -d`,
# and nothing else) and a new image serving a schema it does not match. Its exit
# status IS the mechanism: compose gates the app containers on it completing
# successfully, so these tests assert the status, not just the log line.


def test_check_exits_non_zero_when_migrations_are_pending(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A pending migration must REFUSE the swap — a clean exit here deploys it."""
    baseline = next(p for p in migrate._migration_files() if p.stem == "0001_initial")
    monkeypatch.setattr(migrate, "pending_migrations", lambda: [baseline])

    with pytest.raises(SystemExit) as exit_info:
        migrate._check()

    assert exit_info.value.code != 0, "a pending migration exited 0 — compose would deploy it"


def test_check_names_the_pending_migrations(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    """A refusal that does not say what it is refusing over is just an outage."""
    baseline = next(p for p in migrate._migration_files() if p.stem == "0001_initial")
    monkeypatch.setattr(migrate, "pending_migrations", lambda: [baseline])

    with caplog.at_level("ERROR"), pytest.raises(SystemExit):
        migrate._check()

    assert "0001_initial" in caplog.text
    assert "infra/deploy.sh" in caplog.text, "the refusal must point at the path that fixes it"


def test_check_returns_cleanly_when_the_schema_is_current(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The common case — a code-only release must sail through the button."""
    monkeypatch.setattr(migrate, "pending_migrations", list)
    migrate._check()  # no SystemExit


def test_check_never_applies_anything(monkeypatch: pytest.MonkeyPatch) -> None:
    """⛔ The preflight INSPECTS. It runs before the backup and before the stop.

    A `--check` that quietly applied what it found would move the schema under the
    still-running old containers with no dump taken — strictly worse than the button
    it exists to make safe.
    """
    baseline = next(p for p in migrate._migration_files() if p.stem == "0001_initial")
    monkeypatch.setattr(migrate, "pending_migrations", lambda: [baseline])

    def _explode(path: object) -> None:
        raise AssertionError(f"the preflight applied {path}")

    monkeypatch.setattr(migrate, "_apply_one", _explode)

    with pytest.raises(SystemExit):
        migrate._check()


def test_main_dispatches_check_instead_of_applying(monkeypatch: pytest.MonkeyPatch) -> None:
    """`--check` must reach `_check` — a flag parsed wrong runs the real migration."""
    monkeypatch.setattr(sys, "argv", ["healthee.db.migrate", "--check"])

    def _explode() -> list[str]:
        raise AssertionError("main() applied migrations despite --check")

    monkeypatch.setattr(migrate, "apply_migrations", _explode)
    monkeypatch.setattr(migrate, "pending_migrations", list)

    migrate.main()


def test_main_without_the_flag_still_applies(monkeypatch: pytest.MonkeyPatch) -> None:
    """The reverse direction: the preflight must not have disarmed the real deploy."""
    monkeypatch.setattr(sys, "argv", ["healthee.db.migrate"])
    called: list[bool] = []
    monkeypatch.setattr(migrate, "apply_migrations", lambda: called.append(True) or [])

    migrate.main()

    assert called, "main() no longer applies migrations when --check is absent"
