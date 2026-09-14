-- 0022_subscription_coach_questions — one owner's coach cap, not only the deployment's.
--
-- ## The gap
--
-- `PREMIUM_COACH_QUESTIONS` is read once for the whole deployment, so a box could give
-- every premium owner 20 questions or every one of them unlimited, and nothing in
-- between. An operator opening their server to guests had to cap themselves to cap the
-- guests. The ledger already counted per owner (`kv`, `allowance:coach:30d`); only the
-- LIMIT was global.
--
-- ## Why here, on the entitlement row
--
-- What an owner is entitled to already lives in `subscription`, read per request by
-- `core/entitlement.py` and written only by `db/grant_premium.py` and 6.6b's webhook. A
-- per-owner cap kept in config instead would be a second source of truth that the
-- webhook could not see.
--
-- ## NULL, 0 and N mean three different things
--
--   NULL  -> the deployment's PREMIUM_COACH_QUESTIONS (every existing row, unchanged)
--   0     -> unlimited, matching what 0 already means for the deployment setting
--   N > 0 -> N coach questions per rolling window
--
-- NULL is the default, so this migration changes nobody's cap on the way in.
--
-- Replay-safe; `migrate._apply_one` runs the file plus its ledger row in ONE transaction.

ALTER TABLE subscription ADD COLUMN IF NOT EXISTS coach_questions INTEGER;

ALTER TABLE subscription DROP CONSTRAINT IF EXISTS subscription_coach_questions_chk;
ALTER TABLE subscription ADD CONSTRAINT subscription_coach_questions_chk
  CHECK (coach_questions IS NULL OR coach_questions >= 0);

COMMENT ON COLUMN subscription.coach_questions IS
  'This owner''s coach cap per rolling window. NULL defers to the deployment''s '
  'PREMIUM_COACH_QUESTIONS, 0 is unlimited, N is N. Written by db/grant_premium.py.';
