"""One-off: move the sentinel owner's data to the real Supabase owner (6.4c, §8/§4.5).

Every row of health data predating auth belongs to the sentinel owner
(`00000000-…-0000`). When the real owner first signs in with Supabase they are
JIT-provisioned under a *real* UUID — and would open the app to an empty account.
This module re-keys the sentinel's `app_user` row to that UUID, taking every
dependent row with it.

Run it as a module, the same way migrations are run::

    uv run python -m healthee.db.claim_sentinel <target-uuid>            # DRY RUN
    uv run python -m healthee.db.claim_sentinel <target-uuid> --apply    # for real

**It is run ONCE, deliberately, by an operator — never automatically, and never from
the auth path.** "The first user to sign in claims all the data" would be a
catastrophic security hole: anyone who signed up first would inherit a stranger's
complete health history. The operator naming the UUID is the authorisation.

## Why the target UUID is a CLI argument

The most explicit and auditable form for a one-off: it appears in the command, the
shell history, and the log line, and it cannot be silently inherited from a stale
env var or config file that someone set months ago for a different purpose. Combined
with the dry run — which prints the target's **email** before anything changes — the
operator confirms *who* they are handing the data to, not just that a UUID parsed.

## The mechanism: one cascading UPDATE

`UPDATE app_user SET id = <target> WHERE id = <sentinel>` — and every FK to
`app_user(id)` carries `ON UPDATE CASCADE` (0003 for the 16 data tables; 0006 for
`device_token`), so every dependent row moves atomically. This is chosen over a
hand-written list of per-table UPDATEs precisely because that list can silently miss
a table someone adds later; the cascade cannot miss one, because the database itself
enumerates them.

Identity is preserved deliberately, not incidentally: the sentinel row carries
`email = NULL` and the legacy timezone, while the target's JIT-provisioned row holds
their **real** email and timezone. A naive cascade would leave the surviving row
wearing the sentinel's values and lose the real email, so the target's identity
fields are captured, their row is removed to free the primary key, and the re-keyed
row is stamped with them in the same statement.

Safety: dry-run by default; refuses anything ambiguous rather than guessing; and the
whole apply runs in ONE transaction ending in a post-check that no row anywhere still
belongs to the sentinel — the real net, since it catches a missed table regardless of
mechanism. Any failure rolls the entire re-key back.

## Why it connects as the ADMIN, not the app pool

It re-keys `app_user` itself and must see across ALL owners at once. Under 6.5b-2's
Row-Level Security an app-role connection would silently filter both the counts and
`_verify`'s post-check to the current tenant — i.e. to nothing — and the post-check
would report a clean pass over a re-key it never actually looked at. A verification
that cannot see what it is verifying is worse than none, so this runs as the owner
(`core.db.admin_connection`; Phase 6.5b-1, MULTI_USER.md §3.3).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from uuid import UUID

from psycopg import Cursor, sql
from psycopg.rows import TupleRow

from healthee.core.db import admin_connection
from healthee.core.logging import configure_logging, get_logger
from healthee.core.tenancy import SENTINEL_USER_ID

log = get_logger(__name__)

# `device_token` and `enrollment_code` (0023) reference app_user but hold credentials,
# not owned data: an owner who paired a device before claiming is not an "ambiguous
# merge", so they are excluded from the table list this tool REPORTS and counts. They
# are NOT excluded from the post-check — nothing may still reference the sentinel.
_NON_TENANT_TABLES = frozenset({"device_token", "enrollment_code"})

# The narrower list: tenant tables that hold no HEALTH data, so a row in one of them
# cannot make a claim an ambiguous merge. `subscription` is a tenant table and stays one
# — the entitlement is the owner's and rides the re-key with everything else — but it is
# not a reason to REFUSE, and treating it as one had a real cost.
#
# The sequence that reached it is the ordinary one: the owner signs in, the operator
# comps them (`db/grant_premium.py` requires an `app_user` row, so a grant BEFORE the
# claim is the natural order), and the claim was then refused permanently — `--revoke`
# writes `status = 'canceled'` through the same upsert and nothing deletes from the
# table, so there was no shipped way out and the operator was left hand-writing SQL. The
# refusal was also the wrong DIAGNOSIS, which matters more than the inconvenience: it
# told the operator their target owns health data when it owns none.
#
# Kept separate from `_NON_TENANT_TABLES` rather than folded into it, because the two
# answer different questions: that one is "what does this tool move and report", this
# one is "what makes two owners a merge". Folding them would have quietly dropped
# `subscription` out of the plan's own counts.
_NON_HEALTH_TABLES = _NON_TENANT_TABLES | {"subscription"}


class ClaimRefusedError(Exception):
    """The claim is ambiguous or unsafe — refuse rather than guess."""


@dataclass(frozen=True)
class ClaimPlan:
    """What the claim would move, and to whom."""

    target: UUID
    email: str | None
    timezone: str
    counts: dict[str, int]  # tenant table → rows currently owned by the sentinel
    # Whether the sentinel's own entitlement row is about to be replaced by the
    # target's. Reported before `--apply`; see `_entitlement_superseded`.
    entitlement_superseded: bool = False

    @property
    def total(self) -> int:
        return sum(self.counts.values())


def referencing_tables(cur: Cursor[TupleRow]) -> list[str]:
    """Every public table with a FK to `app_user(id)` — asked of the database.

    The canonical list, discovered rather than hand-copied: a table added next month
    appears here automatically, so neither the report nor the post-check can silently
    omit it. Hypertable chunks are excluded by namespace (they inherit `sample`'s FK
    and are counted through their parent).
    """
    cur.execute(
        "SELECT DISTINCT c.conrelid::regclass::text FROM pg_constraint c "
        "JOIN pg_class t ON t.oid = c.conrelid "
        "WHERE c.contype = 'f' AND c.confrelid = 'app_user'::regclass "
        "AND t.relnamespace = 'public'::regnamespace ORDER BY 1"
    )
    return [row[0] for row in cur.fetchall()]


def tenant_tables(cur: Cursor[TupleRow]) -> list[str]:
    """The referencing tables that hold owned DATA (i.e. minus the identity tables)."""
    return [t for t in referencing_tables(cur) if t not in _NON_TENANT_TABLES]


def _count_rows(cur: Cursor[TupleRow], table: str, user_id: UUID) -> int:
    """Rows in `table` owned by `user_id`.

    The table name is a psycopg `Identifier`, not an f-string: it comes from the
    catalog above and never from user input, but composing identifiers properly is
    the only form that cannot be injected regardless of where the name came from.
    """
    cur.execute(
        sql.SQL("SELECT count(*) FROM {} WHERE user_id = %s").format(sql.Identifier(table)),
        (user_id,),
    )
    row = cur.fetchone()
    return int(row[0]) if row else 0


def _counts(cur: Cursor[TupleRow], tables: list[str], user_id: UUID) -> dict[str, int]:
    """Per-table row counts for one owner, keeping only the tables that hold rows."""
    counted = {table: _count_rows(cur, table, user_id) for table in tables}
    return {table: n for table, n in counted.items() if n}


def _identity(cur: Cursor[TupleRow], user_id: UUID) -> tuple[str | None, str] | None:
    """`(email, timezone)` from `app_user`, or None when the owner has no row."""
    cur.execute("SELECT email, timezone FROM app_user WHERE id = %s", (user_id,))
    row = cur.fetchone()
    return (row[0], row[1]) if row else None


def plan(cur: Cursor[TupleRow], target: UUID) -> ClaimPlan | None:
    """Validate the claim and describe it. None ⇒ nothing to do (a clean no-op).

    Refuses (rather than guessing) when the target is the sentinel itself, has never
    signed in, or already owns data.
    """
    if target == SENTINEL_USER_ID:
        raise ClaimRefusedError("the target is the sentinel itself — nothing to claim")
    if _identity(cur, SENTINEL_USER_ID) is None:
        log.info("no sentinel owner row — already claimed, or never seeded. Nothing to do.")
        return None
    identity = _identity(cur, target)
    if identity is None:
        raise ClaimRefusedError(
            f"no app_user row for {target} — that owner has never signed in. Sign in once "
            "with Supabase (which provisions the row), then re-run. Refusing rather than "
            "creating the row here: an unverified UUID may be a typo, and re-keying a "
            "life's health data onto a stranger or a ghost is not undoable by a re-run."
        )
    tables = tenant_tables(cur)
    owned = _counts(cur, tables, target)
    health = {t: n for t, n in owned.items() if t not in _NON_HEALTH_TABLES}
    if health:
        raise ClaimRefusedError(
            f"{target} already owns data ({health}) — this tool re-keys, it does not merge. "
            "Merging two owners' health data is a judgement call about whose numbers are "
            "whose, and it is not this tool's to make."
        )
    counts = _counts(cur, tables, SENTINEL_USER_ID)
    return ClaimPlan(
        target=target,
        email=identity[0],
        timezone=identity[1],
        counts=counts,
        entitlement_superseded=_entitlement_superseded(cur, target),
    )


def _has_subscription(cur: Cursor[TupleRow], user_id: UUID) -> bool:
    """Whether `user_id` holds an entitlement row. `subscription.user_id` is its PK."""
    cur.execute("SELECT 1 FROM subscription WHERE user_id = %s", (user_id,))
    return cur.fetchone() is not None


def _entitlement_superseded(cur: Cursor[TupleRow], target: UUID) -> bool:
    """Whether the sentinel's entitlement row is about to be replaced by the target's.

    `subscription.user_id` is the PRIMARY KEY, so at most one row can survive per owner
    and the two cannot be merged. The TARGET's wins, for the same reason step 3 of
    `_rekey` stamps the target's real email and timezone over the sentinel's: entitlement
    belongs to a person, the operator granted that row to a real identified owner after
    they signed in, and the sentinel is the pre-identity placeholder that is about to
    stop existing. Refusing instead would leave the operator hand-writing SQL, which is
    the state this family of ops modules exists to replace — and the discarded row is
    the one thing here that a committed tool CAN restore in one command
    (`python -m healthee.db.grant_premium`), unlike any health row.

    Never silent: `_report` prints this before `--apply` is asked for.
    """
    return _has_subscription(cur, target) and _has_subscription(cur, SENTINEL_USER_ID)


def _report(claim_plan: ClaimPlan) -> None:
    """Log exactly what would move, and to whom — the operator's confirmation surface."""
    log.info("claim plan: %s  →  %s", SENTINEL_USER_ID, claim_plan.target)
    log.info("  target email:    %s", claim_plan.email or "(none mirrored)")
    log.info("  target timezone: %s  (kept — the re-keyed row takes it)", claim_plan.timezone)
    for table, count in sorted(claim_plan.counts.items()):
        log.info("  %-18s %8d rows", table, count)
    log.info("  %-18s %8d rows", "TOTAL", claim_plan.total)
    if claim_plan.entitlement_superseded:
        log.warning(
            "  the target already holds a subscription row: THEIRS is kept and the "
            "sentinel's is dropped (one row per owner — see _entitlement_superseded). "
            "Re-grant with `python -m healthee.db.grant_premium` if that is the wrong one."
        )


def _rekey(cur: Cursor[TupleRow], claim_plan: ClaimPlan) -> None:
    """Free the target's primary key, then cascade the sentinel's whole graph onto it.

    Order matters and is the whole trick:

    1. park the target's device tokens AND their entitlement row on the sentinel, so
       nothing references the target's row (both ride the cascade back in step 3 — the
       alternative, letting step 2 cascade-delete them, would silently break a device
       the owner just paired and silently drop the subscription they were granted).
       `subscription` carries `ON DELETE CASCADE` exactly like `device_token` and needs
       the same treatment, with one extra move: its `user_id` is the PRIMARY KEY, so the
       sentinel's own row is dropped first to make room (`_entitlement_superseded` argues
       why the target's wins, and `_report` says so before `--apply`);
    2. delete the target's row, freeing the primary key the cascade needs;
    3. re-key the sentinel, stamping the target's REAL email + timezone onto the
       surviving row so the cascade doesn't leave it wearing `email = NULL` and the
       legacy zone.
    """
    cur.execute(
        "UPDATE device_token SET user_id = %s WHERE user_id = %s",
        (SENTINEL_USER_ID, claim_plan.target),
    )
    # The target's enrollment codes ride the same way: step 2 would cascade-delete
    # them, and with them the record of which code enrolled which phone.
    cur.execute(
        "UPDATE enrollment_code SET user_id = %s WHERE user_id = %s",
        (SENTINEL_USER_ID, claim_plan.target),
    )
    if _has_subscription(cur, claim_plan.target):
        # One row per owner, and the target's is the one that survives. The sentinel's
        # is deleted FIRST so the park below cannot hit the primary key.
        cur.execute("DELETE FROM subscription WHERE user_id = %s", (SENTINEL_USER_ID,))
        cur.execute(
            "UPDATE subscription SET user_id = %s WHERE user_id = %s",
            (SENTINEL_USER_ID, claim_plan.target),
        )
    cur.execute("DELETE FROM app_user WHERE id = %s", (claim_plan.target,))
    cur.execute(
        "UPDATE app_user SET id = %s, email = %s, timezone = %s WHERE id = %s",
        (claim_plan.target, claim_plan.email, claim_plan.timezone, SENTINEL_USER_ID),
    )


def _verify(cur: Cursor[TupleRow]) -> None:
    """Assert NOTHING belongs to the sentinel any more. Raises ⇒ the caller rolls back.

    The real safety net. It is driven off `referencing_tables()` (the database's own
    list, including the identity tables), so it catches a table the cascade somehow
    missed — a new one, a dropped FK, an action that isn't CASCADE — no matter what
    the mechanism believed. A partial re-key would scatter one person's health history
    across two owners, which is exactly the silent wrongness this repo exists to
    prevent, so it is never left half-applied.
    """
    stragglers = {
        table: n
        for table in referencing_tables(cur)
        if (n := _count_rows(cur, table, SENTINEL_USER_ID))
    }
    if stragglers:
        raise ClaimRefusedError(
            f"post-check FAILED — rows still owned by the sentinel: {stragglers}"
        )
    if _identity(cur, SENTINEL_USER_ID) is not None:
        raise ClaimRefusedError("post-check FAILED — the sentinel app_user row still exists")


def claim(target: UUID, *, apply: bool = False) -> ClaimPlan | None:
    """Plan (and, with `apply`, perform) the sentinel → `target` re-key.

    One transaction: the plan, the re-key, and the post-check all share it, so a failed
    verification rolls the whole thing back rather than leaving data split in two.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        claim_plan = plan(cur, target)
        if claim_plan is None:
            return None
        _report(claim_plan)
        if not claim_plan.total:
            log.info("the sentinel owns no data — nothing to move. Leaving both rows alone.")
            return None
        if not apply:
            log.info("DRY RUN — nothing was changed. Re-run with --apply to perform it.")
            return claim_plan
        _rekey(cur, claim_plan)
        _verify(cur)
        log.info("claimed: %d rows now belong to %s", claim_plan.total, target)
        return claim_plan


def _uuid_arg(raw: str) -> UUID:
    try:
        return UUID(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{raw!r} is not a valid UUID") from exc


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="python -m healthee.db.claim_sentinel",
        description="Move the sentinel owner's health data to a real Supabase owner. "
        "Prints the plan and changes nothing unless --apply is given.",
    )
    parser.add_argument("target", type=_uuid_arg, help="the real owner's Supabase UUID")
    parser.add_argument(
        "--apply", action="store_true", help="actually perform the re-key (default: dry run)"
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. 0 = done (or nothing to do), 2 = refused."""
    configure_logging()
    args = _parse_args(argv)
    try:
        claim(args.target, apply=args.apply)
    except ClaimRefusedError as exc:
        log.error("refused: %s", exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
