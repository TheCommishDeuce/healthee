"""QR enrollment — one-time codes an administrator issues, redeemed for a phone token.

Design and security review: `docs/QR_ENROLLMENT.md`. The two halves run as different
database roles on purpose:

* `issue_enrollment_code` is handed a cursor on the ADMIN connection by the CLI
  (`healthee.db.enroll`). The app role has INSERT on `enrollment_code` revoked, so no
  request path can create a code — which is what "phones cannot enroll phones" means
  as a property rather than a promise.
* `redeem_enrollment_code` runs on the app pool (`POST /api/enroll`), and consumes the
  code and mints the `phone` token in ONE transaction.

Security note: never log a raw code, a raw token or either hash — only ids.
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

from psycopg import Cursor
from psycopg.rows import TupleRow

from healthee.core.db import transaction
from healthee.core.device_token import PHONE_SCOPE, insert_device_token
from healthee.core.logging import get_logger

log = get_logger(__name__)

_CODE_BYTES = 32  # secrets.token_urlsafe entropy: 256 bits, not guessable online

#: How long a code lives unless the administrator says otherwise, and the ceiling.
#: Long enough to walk to the phone and scan; short enough that a photo of the
#: screen taken later is worth nothing.
DEFAULT_TTL = timedelta(minutes=10)
MAX_TTL = timedelta(minutes=60)


class EnrollmentError(ValueError):
    """A request the administrator's CLI must refuse (bad TTL, unknown owner)."""


@dataclass(frozen=True)
class EnrolledPhone:
    """What a successful redemption hands back. `token` exists only here, once."""

    token: str
    token_id: UUID
    user_id: UUID


def _hash_code(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def issue_enrollment_code(
    cur: Cursor[TupleRow], user_id: UUID, label: str | None, ttl: timedelta = DEFAULT_TTL
) -> str:
    """Store a fresh one-time code for `user_id` and return it raw (the only copy).

    `cur` must be on the ADMIN connection (module docstring); on the app role the
    INSERT fails by design. Refuses an owner with no `app_user` row rather than
    letting the FK raise — the operator gets a sentence, not a trace.
    """
    if not timedelta(0) < ttl <= MAX_TTL:
        raise EnrollmentError(f"TTL must be between 1 second and {MAX_TTL}.")
    raw = secrets.token_urlsafe(_CODE_BYTES)
    cur.execute("SELECT 1 FROM app_user WHERE id = %s", (str(user_id),))
    if cur.fetchone() is None:
        raise EnrollmentError(f"No owner with id {user_id}.")
    cur.execute(
        "INSERT INTO enrollment_code (user_id, code_hash, label, expires_at) "
        "VALUES (%s, %s, %s, now() + %s) RETURNING id",
        (str(user_id), _hash_code(raw), label, ttl),
    )
    row = cur.fetchone()
    log.info("enrollment code %s issued for %s", row[0] if row else "?", user_id)
    return raw


def redeem_enrollment_code(raw: str, label: str | None) -> EnrolledPhone | None:
    """Consume `raw` and mint a `phone` token for its owner; None if it is not valid.

    Unknown, already used and expired are ONE answer (None): telling a caller which
    of the three it hit is telling a guesser that a code exists. The consume is a
    single conditional UPDATE, so two phones racing the same code cannot both win —
    the loser's UPDATE matches no row.

    The token's label is the phone's own when it sends one, else the label the
    administrator wrote on the code. The 10-live-token cap applies (409, and the
    code is NOT consumed, because the whole transaction rolls back).
    """
    if not raw:
        return None
    with transaction() as cur:
        cur.execute(
            "UPDATE enrollment_code SET used_at = now() "
            "WHERE code_hash = %s AND used_at IS NULL AND expires_at > now() "
            "RETURNING id, user_id, label",
            (_hash_code(raw),),
        )
        found = cur.fetchone()
        if found is None:
            return None
        code_id, owner, code_label = found
        user_id = owner if isinstance(owner, UUID) else UUID(str(owner))
        token, token_id = insert_device_token(cur, user_id, label or code_label, PHONE_SCOPE)
        cur.execute(
            "UPDATE enrollment_code SET device_token_id = %s WHERE id = %s",
            (str(token_id), str(code_id)),
        )
    log.info("enrollment code %s redeemed as device token %s", code_id, token_id)
    return EnrolledPhone(token=token, token_id=token_id, user_id=user_id)
