# Full-history mirror — contract

Status: **server endpoints + phone download implemented; not deployed.**
Decision: A2 in [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md). The server remains the
canonical history (A1); the mirror is a copy the phone can hold.

## Why months and digests

The history tables are corrected in place (upserts from re-derivation and re-pulls)
and occasionally pruned (`db/stale_derived.py`). None carries a change sequence or
tombstones, and adding them to every table is a large, risky migration. A month
digest captures corrections **and** deletions with no schema change:

- `GET /api/mirror/manifest` →
  `{"version": 1, "streams": {"<stream>": [{"month": "YYYY-MM", "rows": n, "digest": "<md5>"}]}}`
- `GET /api/mirror/<stream>?month=YYYY-MM` →
  `{"version", "stream", "month", "rows", "digest", "items": [<row>, …]}`

The digest is MD5 over the canonical rows (`to_jsonb(row)` minus the owner and
recompute bookkeeping), in key order, computed in SQL with the transaction pinned to
UTC. The month endpoint computes the digest from the very rows it returns, so a
stored month is internally consistent even if data changed between the two calls.

## Streams

| Stream | Month of | Omitted |
|---|---|---|
| `derived_daily` | `day` | `user_id`, `derived_at` |
| `sleep_session` | `start_ts` (UTC) | `user_id` |
| `workout` | `start_ts` (UTC) | `user_id` |
| `weight_log` | `ts` (UTC) | `user_id` |
| `device_daily_total` | `day` | `user_id`, `reported_at` |

**Not mirrored, deliberately:** `sample` (the raw per-minute series). It is orders of
magnitude larger and no screen reads it off the phone; adding it is another row in
`read/mirror.STREAMS` with the same contract if a use appears. Manual journal entries
and GPS tracks are also out: their screens were removed.

## Phone behaviour (`data/mirror/mirror_sync.dart`)

1. `GET /api/account` names the owner; the mirror is keyed by that UUID, so
   re-enrolling the same owner keeps it and a different owner never sees it.
2. For each manifest month, skip it if the stored digest and contract version
   match; otherwise fetch and replace the month whole.
3. Delete stored months the manifest no longer lists.

Each month is its own write: an interrupted run keeps what it wrote and the next run
resumes by comparing digests; repeating a finished run downloads nothing. A contract
version bump refetches everything. Rows live in `mirror_months` (local store v9),
which the upload queue never reads, so mirrored history cannot be re-uploaded.

Trigger: **Settings → Data & sync → Download full history**, which also shows the
records, months, stored size and age. It does not run automatically yet.

## Verification

- Server: `tests/integration/test_mirror.py` (digest equality, UTC bucketing,
  correction/deletion/recompute behaviour, time-zone independence, owner isolation,
  HTTP errors) and contract snapshots `mirror_manifest.json` / `mirror_month.json`.
- Phone: `test/mirror/` (first run, idempotent rerun, changed and dropped months,
  interruption and resume, version bump, owner separation, no upload leakage).

## Not yet done

- No screen reads the mirror yet. Offline fallback for history screens is the next
  use; until then the mirror is a verified local copy.
- Storage on a real multi-year history has not been measured; the card reports the
  actual stored size once run on the phone.
