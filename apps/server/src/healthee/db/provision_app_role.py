"""Provision the least-privilege application role (6.5b-1, MULTI_USER.md §3.3).

Run it as the ADMIN, the same way migrations are run::

    POSTGRES_APP_USER=healthee_app POSTGRES_APP_PASSWORD=<secret> \\
        uv run python -m healthee.db.provision_app_role

## Why this is a module and not a migration

`CREATE ROLE` has no `IF NOT EXISTS`, so making it idempotent needs conditional
logic, and conditional logic in Postgres DDL needs a `DO $$…$$` block — which the
migration runner cannot carry (it splits files on `;`, and psycopg3 runs exactly one
statement per `execute()`). So the branch lives in Python, where it is readable, and
this joins `claim_sentinel` as a committed ops module rather than pasted shell
(CLAUDE.md: "migrations/ops are committed modules, not pasted shell").

It is also not schema: the role is a per-DEPLOYMENT credential whose password comes
from that deployment's environment. A migration is the same everywhere; this is not.

## What it is for

The app connected to Postgres as a **superuser** (verified on the live DB:
`rolsuper=t, rolbypassrls=t`). Superusers bypass Row-Level Security unconditionally
— `FORCE ROW LEVEL SECURITY` does not reach them either — so the §3.3 policies would
have tested green and isolated nothing. This role is the prerequisite that makes RLS
real in 6.5b-2, and least privilege in its own right: an application that can
`DROP TABLE` is a problem regardless of RLS.

The role gets DML on the data tables and nothing else: no TRUNCATE, no DDL, no
ownership, and explicitly `NOSUPERUSER NOBYPASSRLS`. It also carries one login-time
setting (`_ROLE_SETTINGS`) that works around a TimescaleDB planner bug RLS triggers
— see that constant for the reproduction and the measured cost. Because it is a
non-superuser that does NOT own the tables, 6.5b-2 needs only plain `ENABLE ROW
LEVEL SECURITY`; `FORCE` is for when the *connecting* role is the owner.

## Idempotency

Safe to re-run on every deploy: the role is created if absent and updated if
present, and every GRANT is a no-op when already held. Re-running is quiet.

`ALTER DEFAULT PRIVILEGES` is the part that matters over time — a table created by a
FUTURE migration is granted to the app role automatically. Without it the next
`CREATE TABLE` silently locks the app out of its own new table, and the fastest
"fix" for that at 2am is handing back superuser.
"""

from __future__ import annotations

import sys
from typing import LiteralString

from psycopg import Cursor, sql
from psycopg.rows import TupleRow
from pydantic import ValidationError

from healthee.core.config import Settings, get_settings
from healthee.core.db import admin_connection
from healthee.core.logging import configure_logging, get_logger

log = get_logger(__name__)

# The 17 tenant tables (MULTI_USER.md §3.2 + `device_daily_total`, 0017) plus the two
# identity tables the app reads and writes on the auth path: `app_user` (JIT
# provisioning) and `device_token` (pairing). `schema_migrations` is deliberately
# absent — only the admin's migration runner touches it.
_DML_TABLES: tuple[str, ...] = (
    "app_user",
    "challenge",
    "challenge_outcome",
    "coach_commitment",
    "derived_daily",
    "device_daily_total",
    "device_token",
    "finding",
    "gps_point",
    "gps_track",
    "illness_flag",
    "kv",
    "manual_entry",
    "profile",
    "program",
    "recommendation",
    "sample",
    "sleep_session",
    "weight_log",
    "workout",
)

# The BIGSERIAL owners. An INSERT into these tables fails without USAGE on the
# sequence even when the table grant is in place, so they are named, not assumed.
_SEQUENCES: tuple[str, ...] = (
    "challenge_id_seq",
    "coach_commitment_id_seq",
    "program_id_seq",
    "recommendation_id_seq",
)

# Tables the app may READ and must never WRITE (Phase 6.6a, MULTI_USER.md §12.7).
#
# `subscription` is the entitlement row, and entitlement is the one thing a request
# path must be unable to grant itself. Code review is the wrong place for that
# guarantee — it has to be re-made on every future diff — so it is a privilege
# instead: the role the API and the scheduler connect as holds SELECT and nothing
# else, and an INSERT into it fails at the database no matter what SQL anyone writes.
# The webhook that DOES write it (6.6b) runs as the admin, like `claim_sentinel`.
_READ_ONLY_TABLES: tuple[str, ...] = ("subscription",)

# Read + UPDATE only (0023): redeeming a code is an UPDATE, CREATING one enrolls a
# phone and stays with the admin CLI (docs/QR_ENROLLMENT.md).
_REDEEM_ONLY_TABLES: tuple[str, ...] = ("enrollment_code",)

# DML only. TRUNCATE is NOT here on purpose: it is the one DML-shaped privilege that
# can erase a life's health history in one statement, and no request path needs it.
_TABLE_PRIVILEGES = "SELECT, INSERT, UPDATE, DELETE"
_READ_ONLY_PRIVILEGES = "SELECT"
# Everything `ALTER DEFAULT PRIVILEGES` would have handed a new table, minus SELECT.
# It is REVOKEd rather than merely not granted, because the default privileges below
# grant it automatically the moment a migration creates the table — so "we did not
# grant it" is not the same statement as "the role does not have it".
_READ_ONLY_REVOKED = "INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER"
_SEQUENCE_PRIVILEGES = "USAGE, SELECT"
_REDEEM_ONLY_PRIVILEGES = "SELECT, UPDATE"
_REDEEM_ONLY_REVOKED = "INSERT, DELETE, TRUNCATE, REFERENCES, TRIGGER"

# Explicitly denied attributes. Spelled out rather than left to defaults because the
# entire 6.5b-2 security model rests on the first two being false, and a default is
# not a guarantee anyone can read.
_ROLE_ATTRIBUTES = "LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION"

# Per-role settings applied at login (`ALTER ROLE … SET`), as name → value. Annotated
# LiteralString so the composed SQL stays provably constant — the tuple unpack in
# `_apply_role_settings` would otherwise widen these constants to plain `str`.
#
# `timescaledb.enable_skipscan=off` works around an upstream TimescaleDB planner bug
# (reproduced on 2.26.4): a `SELECT DISTINCT ON (…)` over a table carrying an RLS
# policy fails outright with
#
#     InternalError: unsupported subplan type for SkipScan: Result
#
# — the policy's `current_setting()` expression becomes a Result subplan the SkipScan
# custom scan cannot handle. It is not RLS-expression-specific: a STABLE-function
# wrapper around the same lookup was probed and fails identically. `/api/today`'s
# `latest_derived_many` is exactly this shape, so without it the endpoint 500s for
# every user the moment `0008`'s policies are live.
#
# The cost is nil and was measured rather than assumed (661-row `derived_daily`, 200
# runs): median 0.111 ms → 0.127 ms, both plans an index scan on
# `derived_daily_user_idx` — SkipScan only added a skip step on top. Nothing is lost
# on the hypertable path either: `sample` is the only hypertable and no query does
# `DISTINCT ON` against it (the three that do are on plain tables).
#
# Scoped to this ROLE, not the database: the admin bypasses RLS, so it never meets
# the bug and keeps the optimization.
_ROLE_SETTINGS: tuple[tuple[LiteralString, LiteralString], ...] = (
    ("timescaledb.enable_skipscan", "off"),
)


class ProvisionError(Exception):
    """The role cannot be provisioned safely — refuse rather than half-do it."""


def _app_credentials(settings: Settings) -> tuple[str, str]:
    """The app role's name and password from the environment, or refuse.

    The password is NEVER a literal in this file and is never logged. A blank one
    would create a login role that anything on the network can authenticate as, so
    it is refused rather than defaulted — an unusable deploy beats an open one.
    """
    if not settings.postgres_app_user or not settings.postgres_app_password:
        raise ProvisionError(
            "POSTGRES_APP_USER and POSTGRES_APP_PASSWORD must both be set in the "
            "environment. Refusing to create a role without a password."
        )
    return settings.postgres_app_user, settings.postgres_app_password


def _role_exists(cur: Cursor[TupleRow], role: str) -> bool:
    cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,))
    return cur.fetchone() is not None


def _upsert_role(cur: Cursor[TupleRow], role: str, password: str) -> bool:
    """Create the role, or bring an existing one back to these attributes. True ⇒ created.

    The password is composed as an `sql.Literal`, not a `%s` parameter: `CREATE ROLE`
    is a utility statement and Postgres does not accept bind parameters in one.
    `Literal` quotes and escapes it exactly as a parameter would, so there is no
    injection surface — but it does mean the statement (and thus the password) can
    reach the server log if `log_statement = all`. Provision with that off.

    ALTER, not skip-if-present: a role that drifted (someone granted it SUPERUSER to
    unblock something) is silently un-drifted on the next deploy, which is the point
    of running this every time.
    """
    created = not _role_exists(cur, role)
    verb = "CREATE ROLE" if created else "ALTER ROLE"
    cur.execute(
        sql.SQL("{verb} {role} WITH {attrs} PASSWORD {password}").format(
            verb=sql.SQL(verb),
            role=sql.Identifier(role),
            attrs=sql.SQL(_ROLE_ATTRIBUTES),
            password=sql.Literal(password),
        )
    )
    return created


def _apply_role_settings(cur: Cursor[TupleRow], role: str) -> None:
    """Apply `_ROLE_SETTINGS` as login-time defaults for the role. Idempotent (re-SET).

    `ALTER ROLE … SET` takes no bind parameters (a utility statement), so the value is
    an `sql.Literal` — quoted and escaped exactly as a parameter would be. Both name
    and value come from the module constant above, never from input.
    """
    for name, value in _ROLE_SETTINGS:
        cur.execute(
            sql.SQL("ALTER ROLE {role} SET {name} = {value}").format(
                role=sql.Identifier(role),
                name=sql.SQL(name),  # constant from _ROLE_SETTINGS — a GUC name, not input
                value=sql.Literal(value),
            )
        )


def _grant_database_and_schema(cur: Cursor[TupleRow], role: str, database: str) -> None:
    cur.execute(
        sql.SQL("GRANT CONNECT ON DATABASE {db} TO {role}").format(
            db=sql.Identifier(database), role=sql.Identifier(role)
        )
    )
    cur.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {role}").format(role=sql.Identifier(role)))


def _grant_data_privileges(cur: Cursor[TupleRow], role: str) -> None:
    """DML on the data tables + USAGE on their sequences. No TRUNCATE, no DDL.

    Granted table-by-table from an explicit list rather than `ALL TABLES IN SCHEMA
    public`: a wildcard would also hand over `schema_migrations`, and an audit of
    what the app can touch should be readable here, not inferred from the catalog.
    """
    for table in _DML_TABLES:
        cur.execute(
            sql.SQL("GRANT {privs} ON TABLE {table} TO {role}").format(
                privs=sql.SQL(_TABLE_PRIVILEGES),
                table=sql.Identifier(table),
                role=sql.Identifier(role),
            )
        )
    for sequence in _SEQUENCES:
        cur.execute(
            sql.SQL("GRANT {privs} ON SEQUENCE {sequence} TO {role}").format(
                privs=sql.SQL(_SEQUENCE_PRIVILEGES),
                sequence=sql.Identifier(sequence),
                role=sql.Identifier(role),
            )
        )
    _grant_read_only(cur, role)


def _grant_read_only(cur: Cursor[TupleRow], role: str) -> None:
    """SELECT (plus UPDATE for `_REDEEM_ONLY_TABLES`) and an explicit REVOKE of the rest.

    The REVOKE is the load-bearing half. `_grant_future_privileges` sets default
    privileges that hand the app role full DML on any table a later migration creates,
    which is exactly wrong for these tables — so the privileges are taken back here,
    every run. Idempotent: revoking a privilege the role does not hold is a no-op.
    """
    limited: tuple[tuple[tuple[str, ...], LiteralString, LiteralString], ...] = (
        (_READ_ONLY_TABLES, _READ_ONLY_PRIVILEGES, _READ_ONLY_REVOKED),
        (_REDEEM_ONLY_TABLES, _REDEEM_ONLY_PRIVILEGES, _REDEEM_ONLY_REVOKED),
    )
    for tables, granted, revoked in limited:
        for table in tables:
            cur.execute(
                sql.SQL("GRANT {privs} ON TABLE {table} TO {role}").format(
                    privs=sql.SQL(granted),
                    table=sql.Identifier(table),
                    role=sql.Identifier(role),
                )
            )
            cur.execute(
                sql.SQL("REVOKE {privs} ON TABLE {table} FROM {role}").format(
                    privs=sql.SQL(revoked),
                    table=sql.Identifier(table),
                    role=sql.Identifier(role),
                )
            )


def _grant_future_privileges(cur: Cursor[TupleRow], role: str, admin: str) -> None:
    """Auto-grant anything a FUTURE migration creates, so nobody has to remember.

    Scoped `FOR ROLE <admin>` because default privileges attach to the CREATING
    role: the migration runner is the admin, so that is the role whose new tables
    must carry the grant.
    """
    # Annotated LiteralString so the composed SQL stays provably constant — the
    # tuple unpack would otherwise widen these module constants to plain `str`.
    grants: tuple[tuple[LiteralString, LiteralString], ...] = (
        ("TABLES", _TABLE_PRIVILEGES),
        ("SEQUENCES", _SEQUENCE_PRIVILEGES),
    )
    for objects, privileges in grants:
        cur.execute(
            sql.SQL(
                "ALTER DEFAULT PRIVILEGES FOR ROLE {admin} IN SCHEMA public "
                "GRANT {privs} ON {objects} TO {role}"
            ).format(
                admin=sql.Identifier(admin),
                privs=sql.SQL(privileges),
                objects=sql.SQL(objects),
                role=sql.Identifier(role),
            )
        )


def _verify(cur: Cursor[TupleRow], role: str) -> None:
    """Assert the role really cannot bypass RLS. Raises ⇒ the caller rolls back.

    The one check worth failing the whole run over: every isolation guarantee
    6.5b-2 makes is void if this role turns out to be a superuser, and "we granted
    NOSUPERUSER" is not the same claim as "the database says it is not one".
    """
    cur.execute(
        "SELECT rolsuper, rolbypassrls, rolcanlogin FROM pg_roles WHERE rolname = %s", (role,)
    )
    row = cur.fetchone()
    if row is None:
        raise ProvisionError(f"post-check FAILED — role {role!r} does not exist after provisioning")
    is_super, bypasses_rls, can_login = row
    if is_super or bypasses_rls:
        raise ProvisionError(
            f"post-check FAILED — {role!r} has rolsuper={is_super} rolbypassrls={bypasses_rls}; "
            "it would bypass Row-Level Security and must not serve the app"
        )
    if not can_login:
        raise ProvisionError(
            f"post-check FAILED — {role!r} cannot log in; the app could not connect"
        )


def provision() -> str:
    """Create-or-update the app role and its grants. Returns the role name.

    One transaction: role, grants, default privileges and the post-check share it,
    so a failed verification leaves no half-privileged role behind.
    """
    settings = get_settings()
    role, password = _app_credentials(settings)
    with admin_connection() as conn, conn.cursor() as cur:
        created = _upsert_role(cur, role, password)
        _apply_role_settings(cur, role)
        _grant_database_and_schema(cur, role, settings.postgres_db)
        _grant_data_privileges(cur, role)
        _grant_future_privileges(cur, role, settings.postgres_user)
        _verify(cur, role)
    _report(role, created=created, database=settings.postgres_db)
    return role


def _report(role: str, *, created: bool, database: str) -> None:
    """Say what was granted — never the password."""
    log.info("%s app role %r on database %r", "created" if created else "updated", role, database)
    log.info("  attributes:  %s", _ROLE_ATTRIBUTES)
    log.info(
        "  tables:      %s on %d tables (no TRUNCATE, no DDL)", _TABLE_PRIVILEGES, len(_DML_TABLES)
    )
    log.info(
        "  read-only:   %s on %s (writes REVOKED — entitlement is not app-settable)",
        _READ_ONLY_PRIVILEGES,
        ", ".join(_READ_ONLY_TABLES),
    )
    log.info("  sequences:   %s on %s", _SEQUENCE_PRIVILEGES, ", ".join(_SEQUENCES))
    log.info("  future:      default privileges set — new tables are granted automatically")
    log.info("  settings:    %s", ", ".join(f"{n}={v}" for n, v in _ROLE_SETTINGS))
    log.info("Set POSTGRES_APP_USER=%s (+ POSTGRES_APP_PASSWORD) on the app, then restart.", role)


def main() -> int:
    """CLI entry point. 0 = provisioned, 2 = refused.

    `ValidationError` is caught alongside `ProvisionError` because the most likely
    operator slip — exporting the app user but not the password — is rejected by
    `Settings` before this module gets a say, and `configure_logging()` builds
    Settings too. Both are the same event to whoever ran the command ("your config
    is wrong, here is which part"), and a 20-frame pydantic traceback communicates
    that worse than one line. It is reported and exits non-zero, never swallowed.
    """
    try:
        configure_logging()
        provision()
    except (ProvisionError, ValidationError) as exc:
        log.error("refused: %s", exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
