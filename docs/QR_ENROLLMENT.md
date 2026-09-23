# QR enrollment — design and security review

Status: **server + app implemented behind the existing sign-in; not deployed.**
Decisions: I1–I4 in [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md). This replaces
email/password setup *after* it is verified on the owner's phone; until then both
paths work side by side.

## Flow

1. The administrator runs, on the server host:

   ```sh
   python -m healthee.db.enroll issue --email owner@example.com \
       --server-url https://health.example.com --label "Pixel 8"
   ```

   It resolves the **existing** `app_user` row (same UUID, so every historical row
   stays the owner's), stores the SHA-256 of a fresh 256-bit code with a 10-minute
   expiry, and prints a QR plus the same URI as text:
   `healthee://enroll?v=1&server=<url>&code=<code>`.
2. The phone scans it (or the owner pastes the URI), and calls
   `POST /api/enroll {code, label}` on that server with **no** credential.
3. In one transaction the server consumes the code (unused, unexpired) and mints a
   `phone`-scope device token for the code's owner. The raw token is returned once.
4. The phone stores `{server, token, kind: enrolled}` in the keystore and sends that
   token on both `/api/*` and `/ingest/*`.

## Credentials after this change

| Credential | Minted by | Accepted on | Can mint others |
|---|---|---|---|
| Supabase/GoTrue JWT | identity provider | `/api/*` | yes (`POST /api/device`) |
| device token, scope `ingest` | `POST /api/device` (JWT) | `/ingest/*` | no |
| device token, scope `phone` (`hph_…`) | `POST /api/enroll` (one-time code) | `/api/*`, `/ingest/*` | **no** |
| enrollment code | admin CLI only | `POST /api/enroll`, once | — |

## Security properties and how each is enforced

- **Only an administrator can enroll a phone.** The app database role holds
  `SELECT, UPDATE` on `enrollment_code` and has `INSERT` explicitly revoked
  (`provision_app_role._REDEEM_ONLY_TABLES`), so no request path can create a code
  whatever SQL it runs. Codes are created over the admin connection by the CLI.
- **Phones cannot enroll phones.** The device-management endpoints keep requiring a
  JWT (`SupabaseUser`); a phone credential there is a 401.
- **Codes are single-use, short-lived and unguessable.** 256 bits of entropy,
  stored hashed, consumed with one `UPDATE … WHERE used_at IS NULL AND expires_at >
  now() RETURNING` (no check-then-write race). TTL defaults to 10 minutes, max 60.
  Unknown, used and expired codes return the same 401 text (no oracle). The edge
  applies the sign-in rate limit to `/api/enroll` as defence in depth.
- **Phone credentials are revocable and bounded.** They are ordinary `device_token`
  rows: hashed at rest, counted in the 10-live-token cap, listed and revoked by the
  CLI (`devices`, `revoke`). A revoked token is refused on both paths.
- **Least privilege between the two token kinds.** An `ingest` token still cannot
  read (`/api/*` only accepts the `phone` scope); `phone` tokens are recognisable by
  prefix so an opaque string is refused before any database lookup.
- **Owner isolation is unchanged.** The credential resolves to an owner UUID and
  every read still runs under `tenant_transaction` / RLS.

Accepted risk: a phone credential is a long-lived bearer token for reads as well as
writes. That is the explicit trade for removing passwords from a personal install;
mitigations are hashing, per-phone revocation and the keystore on the phone.

## Recovery

Server shell access is the recovery path: `issue` a new code for the same email,
`revoke` the lost phone's token id. Nothing on the phone can do either.

## Migration and compatibility

- Existing owner: `issue --email` targets the existing row; no UUID changes.
- A fresh install without an identity provider: `issue --create-owner --email …
  --timezone …` creates the owner row first.
- Installed older apps keep working: JWT and `ingest` tokens are untouched.
- Removing GoTrue from `infra/` and the email form from the app is a **separate**
  change, only after enrollment is verified on the real phone.
- Unsent strap data survives switching to an enrolled session for the **same**
  owner: pending rows are not session-scoped and upload with the new token. Switching
  to a different owner is not made safe by this change (see offline checks).
