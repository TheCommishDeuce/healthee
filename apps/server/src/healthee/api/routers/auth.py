"""Identity HTTP layer — who this deployment is, and who you are on it.

`GET /api/auth-config` and `POST /api/enroll` are the **unauthenticated** endpoints
here, and they have to be: a client needs to know which identity provider to sign in
against, or to redeem a one-time enrollment code, BEFORE it holds a credential.
`GET /api/me` takes either `/api/*` credential; the device endpoints take a JWT.

Thin by design (standards §2): the `current_user` dependency verifies the Supabase
access JWT and resolves the tenant, the handler shapes one typed response. No SQL
and no business logic here — provisioning + token minting live in
`healthee.core.supabase_auth`.

The device endpoints stay **Supabase-JWT only** — deliberately NOT
`core.request_auth.CurrentUser`, which also accepts an enrolled phone's token. Minting a
device token is minting a long-lived credential, and a phone that could mint more could
enroll phones; that stays with a signed-in identity or the administrator's CLI
(`docs/QR_ENROLLMENT.md`).
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from healthee.core.config import get_settings
from healthee.core.device_token import (
    list_device_tokens,
    mint_device_token,
    revoke_device_token,
)
from healthee.core.enrollment import redeem_enrollment_code
from healthee.core.request_auth import CurrentUser
from healthee.core.supabase_auth import RequestUser, current_user

router = APIRouter(prefix="/api", tags=["auth"])

# The authenticated tenant, injected by the Supabase-JWT dependency. Annotated
# form (not a `Depends(...)` default) keeps ruff B008 happy and reads cleanly. Named
# apart from `request_auth.CurrentUser` because it is strictly narrower: JWT only.
SupabaseUser = Annotated[RequestUser, Depends(current_user)]


class MeResponse(BaseModel):
    """The authenticated user's identity + resolved timezone."""

    id: UUID
    timezone: str


class DeviceTokenResponse(BaseModel):
    """A freshly minted device ingest token — returned exactly once.

    `id` is the TOKEN's id (`device_token.id`), not the owner's. It used to be
    `user.id`: not wrong data, but the wrong subject on a response about a token, and
    the reason a future `DELETE /api/device/{id}` had nothing to address a token by.
    The owner's own id is what `GET /api/me` is for.
    """

    device_token: str
    id: UUID


class AuthConfigResponse(BaseModel):
    """Which identity provider to sign in against, or that there is not one."""

    supabase_url: str | None
    supabase_anon_key: str | None


def _supabase_url() -> str:
    """The project URL, explicit or derived from the project ref.

    Hosted Supabase is always `https://<ref>.supabase.co`, so a deployment that
    already configured `SUPABASE_PROJECT_REF` for JWT verification does not have to
    repeat itself. `SUPABASE_URL` is for a self-hosted GoTrue, which has no ref.
    """
    settings = get_settings()
    if settings.supabase_url:
        return settings.supabase_url.rstrip("/")
    if settings.supabase_project_ref:
        return f"https://{settings.supabase_project_ref}.supabase.co"
    return ""


@router.get("/auth-config", response_model=AuthConfigResponse)
def auth_config() -> AuthConfigResponse:
    """The identity provider this server expects its app to use. **Unauthenticated.**

    ## Why this is public, and why that is not a leak

    Both values are public by construction. The URL names a project. The **anon**
    key is the one Supabase documents as shipping inside clients: it identifies the
    project and authorises nothing on its own, because every row policy still
    applies to whatever it is used to request. The key that bypasses policies is
    `service_role`, it is configured separately, and it is served nowhere.

    It cannot be authenticated even in principle — this is the call a client makes
    in order to find out how to authenticate.

    ## Why it exists

    Without it the app must be COMPILED against one Supabase project, which makes a
    published APK the author's app rather than anybody's: install it and you are
    pointed at their identity provider and their server. For a product whose claim
    is self-hosting, that is backwards. With it, the owner types their server
    address and the app learns the rest.

    ## Nulls are an answer, and a different one from a 404

    A deployment with no identity provider configured gets `200` with nulls, not an
    error: it is a real state (a box running strap-only) and the app can say so. A
    404 means something else entirely — a server too old to have this endpoint —
    and collapsing the two would leave the app unable to tell "this server has no
    login" from "this server predates the question".
    """
    url = _supabase_url()
    key = get_settings().supabase_anon_key
    # Both or neither. Half a configuration is a sign-in form that submits into a
    # 400, which is worse than a screen that says the server has no login set up.
    if not url or not key:
        return AuthConfigResponse(supabase_url=None, supabase_anon_key=None)
    return AuthConfigResponse(supabase_url=url, supabase_anon_key=key)


@router.get("/me", response_model=MeResponse)
def get_me(user: CurrentUser) -> MeResponse:
    """Return the authenticated user's id + timezone (JIT-provisioned on first hit).

    Either `/api/*` credential: "who am I" grants nothing, and an enrolled phone
    uses it to confirm which owner its token belongs to.
    """
    return MeResponse(id=user.id, timezone=user.timezone)


# A device name, not a document. Long enough for "Ashish's Pixel 8 Pro" and short
# enough that the column is not somewhere to put a payload.
_LABEL_MAX = 80


class EnrollRequest(BaseModel):
    """A one-time code from the administrator's QR, and this phone's name."""

    code: str
    label: str | None = None


class EnrollResponse(BaseModel):
    """The phone's own credential, returned exactly once. `id` is the TOKEN's id."""

    device_token: str
    id: UUID
    user_id: UUID


@router.post("/enroll", response_model=EnrollResponse)
def post_enroll(body: EnrollRequest) -> EnrollResponse:
    """Redeem a one-time enrollment code for a `phone`-scope device token.

    Unauthenticated by necessity; the code is the credential (256 bits, single use,
    short-lived, stored hashed). Unknown, used and expired codes share ONE 401 so the
    response never confirms that a code exists. The edge rate-limits this path like
    sign-in. 409 when the owner already holds the maximum live tokens.
    """
    label = body.label.strip()[:_LABEL_MAX] if body.label and body.label.strip() else None
    enrolled = redeem_enrollment_code(body.code.strip(), label)
    if enrolled is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="This enrollment code is not valid. Ask for a new one.",
        )
    return EnrollResponse(
        device_token=enrolled.token, id=enrolled.token_id, user_id=enrolled.user_id
    )


class DeviceTokenRequest(BaseModel):
    """What the caller says this token is for.

    Optional, and free text. The label is the ONLY thing distinguishing one row
    from another in `GET /api/device` — an owner revoking a lost phone is choosing
    between two UUIDs otherwise — so the client is expected to send the device
    name. It is the caller's own string about the caller's own device and it is
    never interpreted, only stored and read back.
    """

    label: str | None = None


@router.post("/device", response_model=DeviceTokenResponse)
def post_device(user: SupabaseUser, body: DeviceTokenRequest | None = None) -> DeviceTokenResponse:
    """Mint a long-lived device ingest token for the authenticated user (once).

    409 when the account already holds `_MAX_LIVE_DEVICE_TOKENS` live ones; the
    body says which state that is and that revoking frees a slot.

    The body is optional so a client that sends none still gets a token: this
    endpoint predates the label, and a mint that started failing on a missing
    field would break the very clients the label exists to help.
    """
    raw, token_id = mint_device_token(user.id, label=_label(body))
    return DeviceTokenResponse(device_token=raw, id=token_id)


def _label(body: DeviceTokenRequest | None) -> str | None:
    """The trimmed label, or None. Blank and absent are the same thing."""
    if body is None or body.label is None:
        return None
    trimmed = body.label.strip()
    return trimmed[:_LABEL_MAX] if trimmed else None


class DeviceListItem(BaseModel):
    """One live device token, as its owner sees it.

    **No token and no hash.** The raw value is unrecoverable by design, and the
    hash is still derived from a live credential — it travels over the wire and
    into whatever the client logs. What an owner needs in order to decide whether
    to revoke something is which one it is and when it was last used.
    """

    id: UUID
    label: str | None
    last_seen: datetime | None
    created_at: datetime


@router.get("/device", response_model=list[DeviceListItem])
def get_devices(user: SupabaseUser) -> list[DeviceListItem]:
    """List the caller's LIVE device tokens, newest first.

    Revocation without listing is not usable — an owner cannot revoke a credential
    they cannot see — so this ships with `DELETE` rather than after it. Scoped to
    the caller by `list_device_tokens`, which puts the owner in the WHERE clause.
    """
    return [
        DeviceListItem(
            id=row.id,
            label=row.label,
            last_seen=row.last_seen,
            created_at=row.created_at,
        )
        for row in list_device_tokens(user.id)
    ]


@router.delete("/device/{token_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(token_id: UUID, user: SupabaseUser) -> None:
    """Revoke one of the caller's device tokens. 404 when there is none to revoke.

    ## The same 404 for somebody else's token and for one that never existed

    `revoke_device_token` puts the owner in the WHERE clause, so a token belonging
    to another account simply matches no row — and this handler cannot tell that
    case from a bad id, which is the correct answer to both. Confirming that an id
    exists but is not yours tells a caller something about an account that is not
    theirs, and a revocation endpoint that enumerated other owners' token ids would
    be a worse leak than the one it was built to close.

    An already-revoked token is also a 404: the owner pressed revoke and nothing
    changed, and saying so is more use than a 204 that implies something did.
    """
    if not revoke_device_token(user.id, token_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No live device token with that id on this account.",
        )
