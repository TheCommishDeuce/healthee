"""Device tokens — the long-lived ingest credential this server mints itself.

Split out of `supabase_auth.py`, which is about the credential we do NOT issue:
Supabase signs the access JWT and this backend only verifies it. These tokens are
the opposite — ours, minted here, and the only thing `/ingest/*` accepts.

They exist because a Supabase access token lives about an hour, and background BLE
sync runs on a phone that has been asleep for six (MULTI_USER.md §4.3). So the two
credentials are not interchangeable and are not meant to be: a JWT says who is
using the app right now, a device token says which device may write to one owner's
history until that owner says otherwise.

## What is stored, and what is not

Only the SHA-256 hash. The raw value is returned exactly once, at mint time, and
never written down — so a database dump is not a set of working credentials, and
neither is a backup of one. The entropy is `secrets.token_urlsafe(32)`.

## The lifecycle this file adds (auth audit C2)

Before it, a token was valid from the moment it was minted until somebody deleted
the row by hand, and nothing in the codebase deleted one. A lost phone kept write
access to that owner's health data permanently. Now: a per-owner cap on how many
can be live, a list an owner can read, and a revocation that takes one back.

Security note: never log a raw token or its hash — only ids and counts.
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from fastapi import HTTPException, status
from psycopg import Cursor
from psycopg.rows import TupleRow

from healthee.core.db import transaction
from healthee.core.logging import get_logger

log = get_logger(__name__)

_DEVICE_TOKEN_BYTES = 32  # secrets.token_urlsafe entropy — ~43 url-safe chars

# How many LIVE device tokens one owner may hold at once (auth audit C2).
#
# `POST /api/device` used to mint on every call with no cap, so one signed-in
# session could create unbounded rows — each one a permanent write credential for
# that owner's health data, and each one invisible until `GET /api/device` existed
# to list them. Ten is not a considered ergonomic limit; it is a bound. An owner
# with ten live tokens has a phone, a spare, and eight they have lost track of,
# which is the state the cap exists to make them notice.
#
# Revoking one frees a slot, which is what makes the refusal actionable rather
# than terminal.
_MAX_LIVE_DEVICE_TOKENS = 10

# The two scopes (0023, docs/QR_ENROLLMENT.md). An INGEST token is minted by a signed-in
# owner through `POST /api/device` and only writes. A PHONE token is minted by
# redeeming an administrator's one-time enrollment code and also reads `/api/*`.
INGEST_SCOPE = "ingest"
PHONE_SCOPE = "phone"

# Phone tokens carry a prefix so `/api/*` can tell one from any other opaque string
# WITHOUT a database lookup: an unprefixed bearer is refused before it costs a query,
# and a leaked phone token is recognisable as one in a log or a secret scan.
PHONE_TOKEN_PREFIX = "hph_"


def too_many_tokens(detail: str) -> HTTPException:
    """A 409 for a mint that would exceed the per-owner cap.

    409, not 403: the caller is allowed to mint device tokens — that is what being
    signed in means here — and this particular request conflicts with the state
    their account is already in. 403 would say "you may not do this", which is
    false and leaves the owner nowhere to go; the body says which state and what
    frees it. The mobile client prints a 409 body verbatim
    (`data/api/problem_message.dart`), so the sentence IS the remedy.
    """
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)


def _hash_token(raw: str) -> str:
    """SHA-256 hex of a device token — the only form we ever store or compare."""
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def mint_device_token(user_id: UUID, label: str | None) -> tuple[str, UUID]:
    """Mint a long-lived device INGEST token for `user_id`; store only its hash.

    Returns `(raw token, the TOKEN's row id)`. The raw value is returned ONCE — it is
    never persisted and cannot be recovered.

    The id is returned because it did not used to be, and `api/routers/auth.py` filled
    the `id` field of its "device token" response with the **user's** id instead: not
    wrong data, but the wrong subject, and the reason a revocation endpoint had nothing
    to address a token by. `device_token.id` is a `gen_random_uuid()` primary key the
    caller otherwise never learns.
    """
    with transaction() as cur:
        return insert_device_token(cur, user_id, label, INGEST_SCOPE)


def insert_device_token(
    cur: Cursor[TupleRow], user_id: UUID, label: str | None, scope: str
) -> tuple[str, UUID]:
    """Mint a token of `scope` inside the CALLER's transaction; `(raw, row id)`.

    Shared by `mint_device_token` and enrollment redemption, which must consume its
    one-time code and create the token atomically — a code marked used with no token
    behind it would strand the phone, and a token without the code consumed would let
    the same code enroll twice.
    """
    prefix = PHONE_TOKEN_PREFIX if scope == PHONE_SCOPE else ""
    raw = prefix + secrets.token_urlsafe(_DEVICE_TOKEN_BYTES)
    # Counted and inserted in ONE transaction: two concurrent mints that each
    # counted nine would each insert a tenth, and the cap would be a suggestion.
    cur.execute(
        "SELECT count(*) FROM device_token WHERE user_id = %s AND revoked_at IS NULL",
        (str(user_id),),
    )
    live = cur.fetchone()
    if live is not None and live[0] >= _MAX_LIVE_DEVICE_TOKENS:
        log.warning("device token refused: %s already holds %s live", user_id, live[0])
        raise too_many_tokens(
            f"This account already has {_MAX_LIVE_DEVICE_TOKENS} device tokens. "
            "Revoke one you no longer use, then try again."
        )
    cur.execute(
        "INSERT INTO device_token (user_id, token_hash, label, scope) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (str(user_id), _hash_token(raw), label, scope),
    )
    row = cur.fetchone()
    if row is None:  # INSERT ... RETURNING always yields the row it just wrote
        raise RuntimeError("device_token insert returned no id")
    token_id = row[0] if isinstance(row[0], UUID) else UUID(str(row[0]))
    return raw, token_id


def resolve_device_token(raw: str, *, phone_only: bool = False) -> UUID | None:
    """Resolve a raw device token to its owner UUID, touching `last_seen`.

    Returns None for an unknown/blank token — the caller distinguishes "no match"
    (None) from a successful lookup (a UUID). `phone_only` is the `/api/*` question:
    an INGEST token must not read, so there it is simply no match.
    """
    if not raw:
        return None
    scope_filter = " AND scope = 'phone'" if phone_only else ""
    with transaction() as cur:
        # `revoked_at IS NULL` in the predicate, not checked after the fact: a
        # revoked token must not have its `last_seen` touched either, or the column
        # that answers "was it used after I revoked it?" would record every attempt
        # as a use.
        cur.execute(
            "UPDATE device_token SET last_seen = now() "
            "WHERE token_hash = %s AND revoked_at IS NULL" + scope_filter + " RETURNING user_id",
            (_hash_token(raw),),
        )
        row = cur.fetchone()
    if row is None:
        return None
    return row[0] if isinstance(row[0], UUID) else UUID(str(row[0]))


@dataclass(frozen=True)
class DeviceTokenRow:
    """One of an owner's device tokens, as they can see it.

    **Never the token.** Not the raw value, which is unrecoverable by design, and
    not the hash either: a hash is still a credential-derived secret, and this
    travels to a client over the wire and into whatever that client logs. What an
    owner needs in order to decide whether to revoke something is which one it is
    and when it was last used, and that is exactly what is here.
    """

    id: UUID
    label: str | None
    last_seen: datetime | None
    created_at: datetime
    scope: str = INGEST_SCOPE


def list_device_tokens(user_id: UUID) -> list[DeviceTokenRow]:
    """Every LIVE device token `user_id` holds, newest first.

    Revoked rows are excluded rather than flagged: this list is the answer to
    "what can currently write to my account?", and a revoked token is not an
    answer to it. The rows stay in the table for the audit question `last_seen`
    exists to settle.

    Revocation without listing is not usable — an owner cannot revoke a token they
    cannot see — which is why this ships in the same change as `revoke_device_token`
    rather than after it.
    """
    with transaction() as cur:
        cur.execute(
            "SELECT id, label, last_seen, created_at, scope FROM device_token "
            "WHERE user_id = %s AND revoked_at IS NULL ORDER BY created_at DESC",
            (str(user_id),),
        )
        rows = cur.fetchall()
    return [
        DeviceTokenRow(
            id=row[0] if isinstance(row[0], UUID) else UUID(str(row[0])),
            label=row[1],
            last_seen=row[2],
            created_at=row[3],
            scope=row[4],
        )
        for row in rows
    ]


def revoke_device_token(user_id: UUID, token_id: UUID) -> bool:
    """Revoke one of `user_id`'s device tokens. True when this call revoked it.

    ## The owner is in the WHERE clause, not in a check above it

    `user_id` is a predicate on the UPDATE rather than a fetch-then-compare, so
    revoking somebody else's token is not a rejected request — it is a statement
    that matches no row. There is no window between the check and the write, and no
    branch that could be reordered into granting one.

    It also means a token id belonging to another owner and a token id that never
    existed are indistinguishable from outside, which is the correct answer to
    both: confirming that an id exists but is not yours tells a caller something
    about an account that is not theirs.

    ## Already-revoked returns False, and that is not an error

    `revoked_at IS NULL` in the predicate makes this idempotent in the useful
    direction: the second call does not move the timestamp, so `revoked_at` keeps
    saying when the credential actually stopped working. The caller decides whether
    "nothing to do" is worth a 404 — `api/routers/auth.py` says it is, because an
    owner who pressed revoke and saw nothing happen deserves to know which of the
    two it was.
    """
    with transaction() as cur:
        cur.execute(
            "UPDATE device_token SET revoked_at = now() "
            "WHERE id = %s AND user_id = %s AND revoked_at IS NULL RETURNING id",
            (str(token_id), str(user_id)),
        )
        return cur.fetchone() is not None
