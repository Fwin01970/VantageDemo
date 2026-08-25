"""
This is the ONE place that decides "who is making this request." Every
protected endpoint depends on get_current_user() below — it never trusts
anything else the request might claim about identity.

Today, verify_token() calls the fake auth module. Later, when real Entra ID
is wired in, only verify_token() changes (to validate a real Microsoft-
signed token instead) — every endpoint using get_current_user() is
untouched.
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError
from sqlalchemy.orm import Session

from app.database import get_db, set_tenant_context
from app.auth.fake_auth import decode_fake_token
from app.services.tenant_resolver import TenantContext, resolve_tenant_context

# HTTPBearer makes the /docs page's "Authorize" button simply ask for the
# token value itself (the string you got back from POST /auth/login) —
# rather than a username/password form, which doesn't match how our login
# actually works. This will be swapped for real Entra ID token validation
# later, but the /docs "Authorize" experience stays the same either way.
bearer_scheme = HTTPBearer()


def verify_token(token: str) -> dict:
    """
    TODO (Phase 1, once Entra ID App Registration exists): replace this
    call with real validation against Entra ID's public keys (JWKS).
    Everything calling this function does not need to change.
    """
    try:
        return decode_fake_token(token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> TenantContext:
    """
    Validates the token, then resolves the full tenant/user/role/permission
    context from the database. Also sets the Postgres session variable that
    activates Row-Level Security for this request.
    """
    claims = verify_token(credentials.credentials)
    user_id = claims.get("sub")
    tenant_id = claims.get("tenant_id")

    if not user_id or not tenant_id:
        raise HTTPException(status_code=401, detail="Token missing required claims")

    # Activate Row-Level Security for this database session BEFORE
    # querying anything else, so even a coding mistake below cannot
    # accidentally return another tenant's rows.
    set_tenant_context(db, tenant_id)

    context = resolve_tenant_context(db, user_id=user_id, tenant_id=tenant_id)
    if context is None:
        raise HTTPException(status_code=401, detail="User or tenant not found")

    return context
