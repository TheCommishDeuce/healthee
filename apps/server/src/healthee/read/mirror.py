"""The full-history mirror — month digests, and one month's rows (docs/MIRROR.md).

DESIGN_DECISIONS A2: the phone may hold the owner's complete history, from an
owner-scoped API rather than a database dump. The server's history tables are
corrected in place (upserts) and occasionally pruned (`db/stale_derived.py`), and
none of them carries a change sequence or tombstones. So the contract is by MONTH:

* the manifest lists, per stream and month, a row count and an MD5 digest of the
  canonical row text;
* the phone fetches only the months whose digest differs from what it holds, and
  replaces each such month whole; a month missing from the manifest is deleted.

Corrections and deletions both change a month's digest, so no schema change is
needed and a download interrupted at any point resumes by comparing again.

Every query runs under the caller's `tenant_transaction`, so RLS scopes it to the
owner; the explicit `user_id` predicate is there for the index, not for safety.
Timestamps are rendered with the transaction pinned to UTC, so a digest does not
depend on the database's configured time zone.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date
from typing import Any
from uuid import UUID

from psycopg import sql

from healthee.derive._common import Cur

#: Bumped when the row shape or the digest recipe changes; the phone refetches all.
MIRROR_VERSION = 1

_MONTH = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")


@dataclass(frozen=True)
class Stream:
    """One mirrored table: which column dates a row, and which columns it carries."""

    table: str
    #: The column that places a row in a month. `DATE` columns bucket by their own
    #: calendar month; `TIMESTAMPTZ` columns by the UTC month.
    dated_by: str
    is_date: bool
    #: Tie-break after the dating column, so the digest order is total.
    also_ordered_by: str | None = None
    #: Columns left out of the row: the owner (implied) and bookkeeping that changes
    #: without the data changing (`derived_at` moves on every recompute).
    omit: tuple[str, ...] = ("user_id",)


#: The mirrored streams. `sample` (the raw per-minute series) is deliberately NOT
#: here: it is orders of magnitude larger and no screen reads it off the phone.
#: `docs/MIRROR.md` records that as a scoped decision, not an oversight.
STREAMS: dict[str, Stream] = {
    "derived_daily": Stream("derived_daily", "day", True, "metric", ("user_id", "derived_at")),
    "sleep_session": Stream("sleep_session", "start_ts", False),
    "workout": Stream("workout", "start_ts", False),
    "weight_log": Stream("weight_log", "ts", False),
    "device_daily_total": Stream(
        "device_daily_total", "day", True, None, ("user_id", "reported_at")
    ),
}


class UnknownMonthError(ValueError):
    """A month parameter that is not `YYYY-MM`."""


def month_bounds(month: str) -> tuple[date, date]:
    """`YYYY-MM` → (first day, first day of the next month)."""
    match = _MONTH.match(month)
    if match is None:
        raise UnknownMonthError(f"month must be YYYY-MM, not {month!r}")
    year, number = int(match.group(1)), int(match.group(2))
    start = date(year, number, 1)
    end = date(year + 1, 1, 1) if number == 12 else date(year, number + 1, 1)
    return start, end


def _row(stream: Stream) -> sql.Composable:
    """`to_jsonb(t) - 'user_id' - …` — the canonical row, as jsonb."""
    expression: sql.Composable = sql.SQL("to_jsonb(t)")
    for column in stream.omit:
        expression = sql.SQL("{} - {}").format(expression, sql.Literal(column))
    return expression


def _order(stream: Stream) -> sql.Composable:
    columns = [sql.Identifier(stream.dated_by)]
    if stream.also_ordered_by:
        columns.append(sql.Identifier(stream.also_ordered_by))
    return sql.SQL(", ").join(columns)


def _month_of(stream: Stream) -> sql.Composable:
    column = sql.Identifier(stream.dated_by)
    if stream.is_date:
        return sql.SQL("to_char({}, 'YYYY-MM')").format(column)
    return sql.SQL("to_char({} AT TIME ZONE 'UTC', 'YYYY-MM')").format(column)


def _utc(cur: Cur) -> None:
    cur.execute("SET LOCAL TIME ZONE 'UTC'")


def manifest(cur: Cur, user_id: UUID) -> dict[str, Any]:
    """Every stream's months, each with its row count and digest, oldest first."""
    _utc(cur)
    streams: dict[str, list[dict[str, Any]]] = {}
    for name, stream in STREAMS.items():
        cur.execute(
            sql.SQL(
                "SELECT {month} AS month, count(*), "
                "md5(string_agg(({row})::text, E'\\n' ORDER BY {order})) "
                "FROM {table} t WHERE user_id = %s GROUP BY 1 ORDER BY 1"
            ).format(
                month=_month_of(stream),
                row=_row(stream),
                order=_order(stream),
                table=sql.Identifier(stream.table),
            ),
            (user_id,),
        )
        streams[name] = [
            {"month": month, "rows": int(count), "digest": digest}
            for month, count, digest in cur.fetchall()
        ]
    return {"version": MIRROR_VERSION, "streams": streams}


def month_rows(cur: Cur, user_id: UUID, name: str, month: str) -> dict[str, Any]:
    """One month of one stream: its rows and the digest of exactly those rows.

    The digest is computed from the same rows in the same query, so a month the
    phone stores is always internally consistent even if the data moved between
    the manifest and this read — the next comparison simply finds it changed.
    """
    stream = STREAMS[name]
    start, end = month_bounds(month)
    _utc(cur)
    column = sql.Identifier(stream.dated_by)
    lower: sql.Composable = sql.Placeholder()
    upper: sql.Composable = sql.Placeholder()
    if not stream.is_date:
        lower = sql.SQL("(%s::date::timestamp AT TIME ZONE 'UTC')")
        upper = sql.SQL("(%s::date::timestamp AT TIME ZONE 'UTC')")
    cur.execute(
        sql.SQL(
            "SELECT coalesce(jsonb_agg({row} ORDER BY {order}), '[]'::jsonb), count(*), "
            "md5(string_agg(({row})::text, E'\\n' ORDER BY {order})) "
            "FROM {table} t WHERE user_id = %s AND {column} >= {lower} AND {column} < {upper}"
        ).format(
            row=_row(stream),
            order=_order(stream),
            table=sql.Identifier(stream.table),
            column=column,
            lower=lower,
            upper=upper,
        ),
        (user_id, start, end),
    )
    found = cur.fetchone()
    items, count, digest = found if found is not None else ([], 0, None)
    return {
        "version": MIRROR_VERSION,
        "stream": name,
        "month": month,
        "rows": int(count),
        "digest": digest,
        "items": items,
    }
