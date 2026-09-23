"""Enroll a phone by QR, list an owner's device tokens, revoke one — the admin CLI.

    uv run python -m healthee.db.enroll issue --email owner@example.com \\
        --server-url https://health.example.com --label "Pixel 8"
    uv run python -m healthee.db.enroll issue --create-owner --email me@example.com \\
        --timezone Europe/Berlin --server-url https://health.example.com
    uv run python -m healthee.db.enroll devices --email owner@example.com
    uv run python -m healthee.db.enroll revoke <token-id>

A committed ops module on the ADMIN connection, like `grant_premium`: **shell access to
the server is the authorisation**, and no request path can do any of this — the app
role cannot even INSERT an enrollment code (`provision_app_role._REDEEM_ONLY_TABLES`).
It is also the recovery path: a lost phone is `revoke`d here and a new one `issue`d,
with nothing on any phone able to do either. Design: `docs/QR_ENROLLMENT.md`.

`issue` targets the EXISTING owner row by email or id, so an enrolled phone reads the
same UUID's history. `--create-owner` is only for an install that has no identity
provider and therefore no owner row yet.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from datetime import timedelta
from urllib.parse import urlencode, urlsplit
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import segno
from psycopg import Cursor
from psycopg.rows import TupleRow

from healthee.core.db import admin_connection
from healthee.core.enrollment import DEFAULT_TTL, EnrollmentError, issue_enrollment_code
from healthee.core.logging import configure_logging

#: The URI the phone's scanner accepts. Versioned so a later payload can change shape
#: without an old app misreading it.
URI_PREFIX = "healthee://enroll"
URI_VERSION = "1"

_DESCRIPTION = "Enroll a phone by QR, list an owner's device tokens, revoke one."


@dataclass(frozen=True)
class Owner:
    """The `app_user` row a command acts on."""

    id: UUID
    email: str | None


def enrollment_uri(server_url: str, code: str) -> str:
    """`healthee://enroll?v=1&server=…&code=…` — what the QR encodes.

    The server must be an absolute http(s) URL: the phone connects to exactly what is
    written here, so a typo is refused now rather than as a failed scan later.
    """
    parts = urlsplit(server_url.strip())
    if parts.scheme not in ("https", "http") or not parts.netloc:
        raise EnrollmentError(f"--server-url must be an absolute http(s) URL, not {server_url!r}")
    server = server_url.strip().rstrip("/")
    return f"{URI_PREFIX}?{urlencode({'v': URI_VERSION, 'server': server, 'code': code})}"


def find_owner(cur: Cursor[TupleRow], *, email: str | None, user_id: UUID | None) -> Owner | None:
    """The owner named by `email` (case-insensitive, `citext`) or `user_id`."""
    if user_id is not None:
        cur.execute("SELECT id, email FROM app_user WHERE id = %s", (str(user_id),))
    else:
        cur.execute("SELECT id, email FROM app_user WHERE email = %s", (email,))
    rows = cur.fetchall()
    if len(rows) != 1:
        return None
    found, mail = rows[0]
    return Owner(id=found if isinstance(found, UUID) else UUID(str(found)), email=mail)


def create_owner(cur: Cursor[TupleRow], email: str, timezone: str) -> Owner:
    """Insert a new `app_user` for an install with no identity provider."""
    try:
        ZoneInfo(timezone)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise EnrollmentError(f"--timezone must be an IANA name, not {timezone!r}") from exc
    cur.execute(
        "INSERT INTO app_user (id, email, timezone) VALUES (gen_random_uuid(), %s, %s) "
        "RETURNING id",
        (email, timezone),
    )
    row = cur.fetchone()
    if row is None:  # INSERT ... RETURNING always yields the row it just wrote
        raise RuntimeError("app_user insert returned no id")
    return Owner(id=row[0] if isinstance(row[0], UUID) else UUID(str(row[0])), email=email)


def _issue(args: argparse.Namespace) -> int:
    enrollment_uri(args.server_url, "x")  # refuse a bad URL before writing anything
    ttl = timedelta(minutes=args.ttl_minutes) if args.ttl_minutes else DEFAULT_TTL
    with admin_connection() as conn, conn.cursor() as cur:
        owner = find_owner(cur, email=args.email, user_id=args.user_id)
        if owner is None and args.create_owner:
            if not args.email or not args.timezone:
                raise EnrollmentError("--create-owner needs --email and --timezone")
            owner = create_owner(cur, args.email, args.timezone)
            print(f"Created owner {owner.id} ({owner.email}).")
        elif owner is None:
            raise EnrollmentError(
                "No single owner matches. Check the email/id, or pass --create-owner "
                "for an install with no identity provider."
            )
        elif args.create_owner:
            raise EnrollmentError(f"An owner already exists: {owner.id}. Drop --create-owner.")
        code = issue_enrollment_code(cur, owner.id, args.label, ttl)
    uri = enrollment_uri(args.server_url, code)
    minutes = int(ttl.total_seconds() // 60)
    print(f"Enrollment for owner {owner.id} ({owner.email or 'no email'}).")
    print(f"Valid once, for {minutes} minutes. Anyone who scans it can read and write")
    print("this owner's health data until the phone's token is revoked.\n")
    segno.make(uri, error="m").terminal(compact=True)
    print(f"\n{uri}")
    return 0


def _devices(args: argparse.Namespace) -> int:
    with admin_connection() as conn, conn.cursor() as cur:
        owner = find_owner(cur, email=args.email, user_id=args.user_id)
        if owner is None:
            raise EnrollmentError("No single owner matches that email/id.")
        cur.execute(
            "SELECT id, scope, label, last_seen, created_at FROM device_token "
            "WHERE user_id = %s AND revoked_at IS NULL ORDER BY created_at DESC",
            (str(owner.id),),
        )
        rows = cur.fetchall()
    print(f"Live device tokens for {owner.id} ({owner.email or 'no email'}): {len(rows)}")
    for token_id, scope, label, last_seen, created_at in rows:
        print(
            f"  {token_id}  {scope:<6}  {label or '-'}  last seen {last_seen or 'never'}"
            f"  created {created_at:%Y-%m-%d}"
        )
    return 0


def _revoke(args: argparse.Namespace) -> int:
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "UPDATE device_token SET revoked_at = now() "
            "WHERE id = %s AND revoked_at IS NULL RETURNING user_id",
            (str(args.token_id),),
        )
        row = cur.fetchone()
    if row is None:
        print(f"No live device token {args.token_id}; nothing changed.")
        return 1
    print(f"Revoked {args.token_id} (owner {row[0]}).")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="healthee.db.enroll", description=_DESCRIPTION)
    commands = parser.add_subparsers(dest="command", required=True)

    def owner_flags(sub: argparse.ArgumentParser) -> None:
        who = sub.add_mutually_exclusive_group(required=True)
        who.add_argument("--email")
        who.add_argument("--user-id", type=UUID)

    issue = commands.add_parser("issue", help="print a one-time enrollment QR")
    owner_flags(issue)
    issue.add_argument("--server-url", required=True)
    issue.add_argument("--label")
    issue.add_argument("--ttl-minutes", type=int, default=0)
    issue.add_argument("--create-owner", action="store_true")
    issue.add_argument("--timezone")
    issue.set_defaults(run=_issue)

    devices = commands.add_parser("devices", help="list an owner's live device tokens")
    owner_flags(devices)
    devices.set_defaults(run=_devices)

    revoke = commands.add_parser("revoke", help="revoke one device token by id")
    revoke.add_argument("token_id", type=UUID)
    revoke.set_defaults(run=_revoke)
    return parser


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    args = _parser().parse_args(argv)
    try:
        return int(args.run(args))
    except EnrollmentError as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
