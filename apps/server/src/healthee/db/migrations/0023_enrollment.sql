-- 0023_enrollment — QR enrollment: one-time codes and phone-scope device tokens.
--
-- Design and security review: docs/QR_ENROLLMENT.md.
--
-- ## device_token.scope
--
-- Every existing token is an INGEST token: minted by `POST /api/device` for a
-- signed-in owner, accepted on `/ingest/*` only. The new `phone` scope is minted by
-- redeeming an enrollment code and is also accepted on `/api/*`. The DEFAULT makes
-- every existing row keep exactly the meaning it had; `ADD COLUMN` with a constant
-- default is a catalogue-only change in PostgreSQL 11+ (no rewrite).
--
-- ## enrollment_code
--
-- Created ONLY by the administrator's CLI over the admin connection; the app role
-- is granted SELECT and UPDATE and has INSERT revoked (`provision_app_role`), so no
-- request path can mint a code. Only the SHA-256 of the code is stored. `used_at`
-- and `device_token_id` record the redemption; the row is kept so an operator can
-- see which code enrolled which phone.
--
-- Not policied, like the other identity tables: redemption has to find the owner
-- from the code before it knows an owner to scope to.
--
-- Replay-safe (IF NOT EXISTS); one statement per `;`.

ALTER TABLE device_token ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'ingest'
  CONSTRAINT device_token_scope_check CHECK (scope IN ('ingest', 'phone'));

CREATE TABLE IF NOT EXISTS enrollment_code (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID         NOT NULL REFERENCES app_user(id)
                                  ON UPDATE CASCADE ON DELETE CASCADE,
  code_hash        TEXT         NOT NULL,
  label            TEXT,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ  NOT NULL,
  used_at          TIMESTAMPTZ,
  device_token_id  UUID         REFERENCES device_token(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS enrollment_code_hash_idx ON enrollment_code (code_hash);
