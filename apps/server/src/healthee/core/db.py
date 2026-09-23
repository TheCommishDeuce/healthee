"""The one database connection pool — every query in the app goes through here.

Decision (handed down): **sync** psycopg3 + `psycopg_pool.ConnectionPool`. The
science layer ports verbatim as synchronous code; FastAPI sync endpoints run in
the threadpool; single-tenant scale doesn't need async. No other module may open
a connection (standards §2: "DB access only via core/db … No module-local
`_connect()`").

Usage — the transaction helper commits on a clean exit and rolls back on any
exception (the pool's own connection context manager does this; we wrap it so
callers get a cursor directly):

    from healthee.core.db import transaction

    with transaction() as cur:
        cur.execute("INSERT INTO sample (user_id, ts, metric, value) VALUES (%s, %s, %s, %s)",
                    (user_id, ts, metric, value))
    # committed here; on exception the whole block is rolled back

Every tenant table needs the owner named explicitly: `0007` dropped the transitional
`user_id` DEFAULT, so a write that omits it now raises NotNullViolation rather than
silently attributing someone's health data to the sentinel.

## Two identities (Phase 6.5b-1, MULTI_USER.md §3.3)

There are TWO credential sets, and the difference is a security boundary:

  * the **app pool** (`get_pool` / `transaction` / `tenant_transaction` /
    `tenant_connection`) connects as the least-privilege `POSTGRES_APP_USER` —
    everything that serves a request or runs a job goes through it. It can
    read/write the data tables and nothing else.
  * `admin_connection()` connects as the owner `POSTGRES_USER` — DDL, TRUNCATE,
    re-keying. It is deliberately awkward and explicitly named; see its docstring
    for the closed list of callers.

The split is the prerequisite for RLS (6.5b-2), not a nicety: a superuser
connection **bypasses Row-Level Security unconditionally**, so policies written
over one are theatre — they test green and protect nothing. So the fallback to the
admin creds is no longer something a blank variable produces: `config.py` refuses to
BOOT without `POSTGRES_APP_*` unless `ALLOW_ADMIN_DB_FALLBACK=true` asks for the
transitional state, and `_refuse_if_privileged` below asks `pg_roles` what the role
actually is and refuses the pool if it bypasses RLS — the two catch different
mistakes, which is why there are two.

## Row-Level Security (Phase 6.5b-2, MULTI_USER.md §3.3)

`0008` put an RLS policy on all 16 tenant tables, keyed on the `healthee.user_id`
GUC. **`tenant_transaction(user_id)` is the ONLY way tenant data is visible to the
app role** — it is what sets that GUC. The consequence is deliberate and worth
stating plainly:

    with transaction() as cur:                  # no owner set
        cur.execute("SELECT count(*) FROM sample")   # -> 0. Always. By design.

A tenant read on a plain `transaction()` returns **zero rows and raises nothing**.
That is RLS failing closed (the alternative, an error, would mean an unset GUC
leaks rows until someone notices), but it means a tenant query left on
`transaction()` shows the user "no data" rather than breaking loudly. The suite
runs as the least-privilege role precisely so that mistake fails a test instead of
reaching a person's health data.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from uuid import UUID

import psycopg
from psycopg import Connection, Cursor
from psycopg.rows import TupleRow
from psycopg_pool import ConnectionPool

from healthee.core.config import get_settings
from healthee.core.logging import get_logger

log = get_logger(__name__)

# Single-tenant scale: a small pool is plenty. Sync FastAPI endpoints run in the
# threadpool (default ~40 workers), so cap well below that to bound DB load.
_POOL_MIN_SIZE = 1
_POOL_MAX_SIZE = 10

_Pool = ConnectionPool[Connection[TupleRow]]
_pool: _Pool | None = None

# The GUC `0008`'s policies read. Named here because this module is the only place
# that ever writes it — the policies are the only place that read it.
_OWNER_GUC = "healthee.user_id"


def _refuse_if_privileged(pool: _Pool) -> None:
    """Refuse the pool when it is connected as a role that BYPASSES RLS.

    A role with `rolsuper` or `rolbypassrls` ignores Row-Level Security entirely —
    `FORCE ROW LEVEL SECURITY` does not touch it either. In a multi-tenant product that
    makes RLS, the backstop under every explicit `AND user_id = %s`, decoration.

    ### Why this is a refusal now, and why it is not the same check as `config.py`'s

    `config.py::_refuse_an_unasked_for_rls_bypass` refuses at BOOT on the config —
    blank `POSTGRES_APP_*`. It cannot see the other route into this state, which is a
    `POSTGRES_APP_USER` that is set and names a privileged role (the admin itself, or a
    role someone later `ALTER`ed). Only the database knows that, which is why this check
    asks `pg_roles` rather than inferring from config, and why both layers exist rather
    than one: they catch different mistakes.

    The old behaviour was a WARNING and a pool that opened anyway — one log line, at the
    moment the deployment stopped isolating its tenants. That is the "a comment claiming
    a guard is not a guard" shape this repo's standards name. A refusal makes the API
    unable to serve rather than able to serve without isolation, which is the direction
    this product errs on purpose.

    `ALLOW_ADMIN_DB_FALLBACK=true` restores the warning, for the one deploy of the
    documented two-deploy bootstrap that has to run on the admin creds
    (`infra/DEPLOY.md` B2 step 1).
    """
    with pool.connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
        )
        row = cur.fetchone()
    if row is None:  # a login role always has a pg_roles row; treat absence as unknown
        log.warning("could not determine the privileges of the connected DB role")
        return
    role, is_super, bypasses_rls = row
    if not (is_super or bypasses_rls):
        log.info("db pool connected as least-privilege role %r", role)
        return
    privilege = "a SUPERUSER" if is_super else "marked BYPASSRLS"
    message = (
        f"the app pool is connected as {role!r}, which is {privilege} — this role "
        f"BYPASSES Row-Level Security, so RLS policies cannot isolate tenants on it. "
        f"Provision the least-privilege role (python -m healthee.db.provision_app_role) "
        f"and set POSTGRES_APP_USER / POSTGRES_APP_PASSWORD."
    )
    if get_settings().allow_admin_db_fallback:
        log.warning("SECURITY: %s (allowed by ALLOW_ADMIN_DB_FALLBACK)", message)
        return
    raise RuntimeError(f"SECURITY: {message}")


def get_pool() -> _Pool:
    """Return the process-wide connection pool, opening it on first use.

    Lazy so importing this module never touches the network or requires config —
    the pool opens the first time a query is actually run. It connects as the
    least-privilege app role (falling back to the admin creds with a WARNING).
    """
    global _pool
    if _pool is None:
        settings = get_settings()
        pool: _Pool = ConnectionPool(
            conninfo=settings.app_db_url,
            min_size=_POOL_MIN_SIZE,
            max_size=_POOL_MAX_SIZE,
            name="healthee",
            open=False,  # explicit open() avoids the constructor-open deprecation
        )
        pool.open()
        log.info(
            "opened db pool: %s:%s/%s (min=%d max=%d)",
            settings.postgres_host,
            settings.postgres_port,
            settings.postgres_db,
            _POOL_MIN_SIZE,
            _POOL_MAX_SIZE,
        )
        # Checked BEFORE the singleton is published, and the pool is closed if it
        # fails: assigning first would mean the second call to `get_pool()` returned
        # the refused pool without re-running the check, so the refusal would apply
        # to exactly one query.
        try:
            _refuse_if_privileged(pool)
        except BaseException:
            pool.close()
            raise
        _pool = pool
    return _pool


def _set_owner(cur: Cursor[TupleRow], user_id: UUID) -> None:
    """Set the GUC `0008`'s policies match on, for this transaction only.

    `SET LOCAL healthee.user_id = %s` is not an option: `SET` is a utility statement
    and Postgres accepts **no bind parameters** in one. The alternative — formatting
    the UUID into the statement text — is the injection-shaped habit this codebase
    refuses (standards §2). `set_config(name, value, is_local)` is an ordinary
    function, so it parameterizes cleanly, and `is_local=true` gives exactly
    SET-LOCAL semantics: the setting reverts when the transaction ends, so an owner
    can never outlive its transaction and reach the next borrower of this pooled
    connection.

    The `execute` itself opens the transaction (psycopg3 connections are not
    autocommit), which is what `is_local=true` requires — it is a no-op with a
    WARNING outside a transaction block.
    """
    cur.execute("SELECT set_config(%s, %s, true)", (_OWNER_GUC, str(user_id)))


@contextmanager
def transaction() -> Iterator[Cursor[TupleRow]]:
    """Borrow a connection and yield a cursor in one transaction. **No owner is set.**

    Commit-on-success / rollback-on-exception is handled by the underlying
    connection context manager.

    Since `0008` this is for the tables with NO policy on them — the identity tables
    (`app_user`, `device_token`) and `/healthz`'s `SELECT 1`. A tenant table read
    through here returns **zero rows** (see the module docstring); use
    `tenant_transaction(user_id)`.
    """
    with get_pool().connection() as conn, conn.cursor() as cur:
        yield cur


@contextmanager
def tenant_connection(user_id: UUID) -> Iterator[Connection[TupleRow]]:
    """`tenant_transaction`'s connection-scoped form — for multi-cursor units of work.

    Two callers, both of which hand the CONNECTION to a collaborator rather than a
    cursor: the ingest push (`ingest/service.py`, one atomic transaction across
    upsert → derive → daily-total override) and the re-derive repair tool
    (`db/rederive.py`) — both because `derive.derive_batch` opens its own cursor.
    The owner is set once, on the connection's transaction, so every cursor opened
    from it is scoped — including the ones the collaborator opens.
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            _set_owner(cur, user_id)
        yield conn


@contextmanager
def tenant_transaction(user_id: UUID) -> Iterator[Cursor[TupleRow]]:
    """Borrow a cursor scoped to ONE owner — **the only way tenant data is readable**.

    Sets the `healthee.user_id` GUC that `0008`'s policies match on (see `_set_owner`
    for why it is `set_config` and not `SET LOCAL`), then yields the cursor.
    Everything that serves a request or runs a job for a known owner goes through
    here; `transaction()` is for the identity tables and `/healthz` only — a tenant
    read on it silently returns nothing (module docstring).

    Commit-on-success / rollback-on-exception is the pooled connection's, exactly as
    in `transaction()`.
    """
    with get_pool().connection() as conn, conn.cursor() as cur:
        _set_owner(cur, user_id)
        yield cur


@contextmanager
def admin_connection() -> Iterator[Connection[TupleRow]]:
    """Borrow a one-shot connection as the OWNER/ADMIN role. **Not for app code.**

    Commits on a clean exit, rolls back on any exception, and closes afterwards —
    unpooled on purpose: this identity can `DROP TABLE`, and a pool of such
    connections sitting around for ordinary code to reach into is precisely the
    problem the app-role split removes. Every request and every job uses
    `tenant_transaction()` / `tenant_connection()` / `transaction()` instead.

    The admin is the table OWNER and `0008` deliberately does not `FORCE` RLS, so
    this connection is **not subject to the tenant policies**. That is the point for
    every caller below — each one has to see across owners — and it is exactly why
    nothing else may use it.

    ### Who may call this, and why — the complete list

    * `db/migrate.py` — DDL. The app role has no `CREATE`/`ALTER`, by design.
    * `db/provision_app_role.py` — creates and grants to the app role; a role
      cannot bootstrap its own privileges.
    * `db/claim_sentinel.py` — re-keys `app_user` and must see across ALL owners.
      On an app-role connection RLS would silently filter its verification SELECTs
      down to nothing and turn the post-check into a false pass — a partial re-key
      reported as success. (The re-key's FK cascades would still work: cascades run
      as the referencing constraint, not under the caller's policies. It is the
      *verification* that would lie, which is the worse failure.)
    * `db/grant_premium.py` — writes `subscription`, on which the app role holds
      SELECT and nothing else BY DESIGN (`db/provision_app_role.py` `_READ_ONLY_TABLES`:
      "a request path cannot mint entitlement"), so the grant tool has to be here.
      This entry was missing while the list said "complete" — a list that claims
      completeness and is not is exactly the artefact a future reader trusts instead
      of grepping.
    * `db/enroll.py` — issues QR enrollment codes, and lists/revokes phone tokens
      across owners for recovery. The app role has INSERT on `enrollment_code`
      revoked BY DESIGN (`_REDEEM_ONLY_TABLES`: phones cannot enroll phones), so the
      administrator's CLI has to be here. `docs/QR_ENROLLMENT.md`.
    * `tests/contracts/seed.py::reset` — `apply_migrations()` + `TRUNCATE`, which
      the app role deliberately cannot do.

    Anything else belongs on the app pool. If you are reaching for this to make a
    permission error go away, the answer is a grant in `provision_app_role`, not a
    superuser connection.
    """
    with psycopg.connect(get_settings().admin_db_url) as conn:
        yield conn


def close_pool() -> None:
    """Close the pool and drop the singleton. Called at app shutdown and between
    tests so the next `get_pool()` rebuilds against fresh config."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None
        log.info("closed db pool")
