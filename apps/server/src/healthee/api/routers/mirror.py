"""Full-history mirror — GET /api/mirror/manifest, GET /api/mirror/{stream}.

Thin (standards §2): authorise, one tenant transaction, the read service, the
payload. Contract and rationale: `read/mirror.py` and `docs/MIRROR.md`. Returns
plain dicts pinned by the contract snapshots (`packages/contracts`), the
documented exception for payloads whose keys are data.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from healthee.core.db import tenant_transaction
from healthee.core.request_auth import CurrentUser
from healthee.read.mirror import STREAMS, UnknownMonthError, manifest, month_bounds, month_rows

router = APIRouter(prefix="/api/mirror", tags=["mirror"])


@router.get("/manifest")
def get_manifest(user: CurrentUser) -> dict:
    """Every mirrored stream's months, with a row count and digest each."""
    with tenant_transaction(user.id) as cur:
        return manifest(cur, user.id)


@router.get("/{stream}")
def get_month(user: CurrentUser, stream: str, month: str) -> dict:
    """One month of one stream: `items`, and the digest of exactly those items."""
    if stream not in STREAMS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="unknown stream")
    try:
        month_bounds(month)
    except UnknownMonthError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    with tenant_transaction(user.id) as cur:
        return month_rows(cur, user.id, stream, month)
