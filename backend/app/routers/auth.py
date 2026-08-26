"""
Real authentication: email/password + generic OAuth (Microsoft, Google,
GitHub, Facebook). Sits alongside auth/fake_auth.py's demo login during
local development — both issue the exact same token shape via
auth/tokens.py, so nothing downstream needs to know which one ran.
"""
import secrets
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from jose import jwt, JWTError
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from sqlalchemy import text

from app import config
from app.database import get_db, set_tenant_context
from app.auth.password import hash_password, verify_password
from app.auth.tokens import issue_access_token
from app.auth.oauth_providers import get_provider, all_providers, extract_identity

router = APIRouter(prefix="/auth", tags=["auth"])

STATE_ALGO = "HS256"


def _make_state() -> str:
    payload = {"nonce": secrets.token_urlsafe(16), "exp": datetime.now(timezone.utc) + timedelta(minutes=10)}
    return jwt.encode(payload, config.OAUTH_STATE_SECRET, algorithm=STATE_ALGO)


def _verify_state(state: str) -> None:
    try:
        jwt.decode(state, config.OAUTH_STATE_SECRET, algorithms=[STATE_ALGO])
    except JWTError:
        raise HTTPException(status_code=400, detail="Invalid or expired sign-in attempt — please try again.")


@router.get("/providers")
def list_providers():
    """Which OAuth providers are actually usable right now — the
    frontend only renders a button for ones that return true here."""
    return {p.name: p.is_configured() for p in all_providers()}


class SignupRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str
    company_name: str
    industry: str = "unspecified"


@router.post("/signup")
def signup(body: SignupRequest, db: Session = Depends(get_db)):
    if len(body.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters.")

    existing = db.execute(
        text("SELECT id FROM find_user_by_email_any_tenant(:email)"), {"email": body.email}
    ).mappings().first()
    if existing:
        raise HTTPException(status_code=409, detail="An account with that email already exists.")

    tenant_row = db.execute(
        text("SELECT create_company_for_admin(:name, :industry) AS id"),
        {"name": body.company_name, "industry": body.industry},
    ).mappings().first()
    tenant_id = str(tenant_row["id"])
    db.execute(text("SELECT seed_default_use_cases_for_tenant(:id)"), {"id": tenant_id})

    user_row = db.execute(
        text("SELECT create_user_for_admin(:tenant_id, :display_name, :email) AS id"),
        {"tenant_id": tenant_id, "display_name": body.display_name, "email": body.email},
    ).mappings().first()
    user_id = str(user_row["id"])

    # Tenant now exists and we know the new user's id — this can be a
    # normal RLS-scoped write instead of another SECURITY DEFINER
    # function, since we're setting context to the tenant that was just
    # created for exactly this user.
    set_tenant_context(db, tenant_id, user_id)
    db.execute(
        text("UPDATE users SET password_hash = :ph, auth_provider = 'local' WHERE id = :id"),
        {"ph": hash_password(body.password), "id": user_id},
    )
    db.commit()

    token = issue_access_token(user_id=user_id, tenant_id=tenant_id)
    return {"access_token": token}


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


@router.post("/login")
def login(body: LoginRequest, db: Session = Depends(get_db)):
    row = db.execute(text("SELECT * FROM find_user_for_login(:email)"), {"email": body.email}).mappings().first()
    if not row:
        # Same error either way — don't reveal whether the email exists.
        raise HTTPException(status_code=401, detail="Incorrect email or password.")

    if row["locked_until"] and row["locked_until"] > datetime.now(timezone.utc):
        raise HTTPException(status_code=423, detail="Too many failed attempts. Try again in a few minutes.")

    if row["auth_provider"] != "local":
        raise HTTPException(
            status_code=400,
            detail=f"This account signs in with {row['auth_provider'].title()} — use that option instead.",
        )

    if not verify_password(body.password, row["password_hash"]):
        db.execute(
            text("SELECT record_login_failure(:id, :threshold, :lock_minutes)"),
            {"id": row["id"], "threshold": config.ACCOUNT_LOCK_THRESHOLD, "lock_minutes": config.ACCOUNT_LOCK_MINUTES},
        )
        db.commit()
        raise HTTPException(status_code=401, detail="Incorrect email or password.")

    db.execute(text("SELECT record_login_success(:id)"), {"id": row["id"]})
    db.commit()

    token = issue_access_token(user_id=str(row["id"]), tenant_id=str(row["tenant_id"]))
    return {"access_token": token}


@router.get("/oauth/{provider_name}/start")
def oauth_start(provider_name: str):
    provider = get_provider(provider_name)
    if not provider or not provider.is_configured():
        raise HTTPException(status_code=501, detail=f"{provider_name.title()} sign-in isn't configured on this server yet.")

    redirect_uri = f"{config.BACKEND_BASE_URL}/auth/oauth/{provider_name}/callback"
    params = {
        "client_id": provider.client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": provider.scope,
        "state": _make_state(),
    }
    query = str(httpx.QueryParams(params))
    return RedirectResponse(f"{provider.authorize_url}?{query}")


@router.get("/oauth/{provider_name}/callback")
def oauth_callback(
    provider_name: str,
    code: str = Query(...),
    state: str = Query(...),
    db: Session = Depends(get_db),
):
    _verify_state(state)
    provider = get_provider(provider_name)
    if not provider or not provider.is_configured():
        raise HTTPException(status_code=501, detail=f"{provider_name.title()} sign-in isn't configured on this server.")

    redirect_uri = f"{config.BACKEND_BASE_URL}/auth/oauth/{provider_name}/callback"

    token_resp = httpx.post(
        provider.token_url,
        data={
            "client_id": provider.client_id,
            "client_secret": provider.client_secret,
            "code": code,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
        headers={"Accept": "application/json"},
        timeout=15,
    )
    if token_resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"{provider.display_name} token exchange failed.")
    access_token = token_resp.json().get("access_token")
    if not access_token:
        raise HTTPException(status_code=502, detail=f"{provider.display_name} did not return an access token.")

    userinfo_resp = httpx.get(provider.userinfo_url, headers={"Authorization": f"Bearer {access_token}"}, timeout=15)
    userinfo = userinfo_resp.json() if userinfo_resp.status_code == 200 else {}

    fallback_emails = None
    if provider.email_fallback_url and not userinfo.get("email"):
        fb_resp = httpx.get(provider.email_fallback_url, headers={"Authorization": f"Bearer {access_token}"}, timeout=15)
        if fb_resp.status_code == 200:
            fallback_emails = fb_resp.json()

    subject, email, display_name = extract_identity(provider_name, userinfo, fallback_emails)
    if not subject:
        raise HTTPException(status_code=502, detail=f"{provider.display_name} didn't return an identity we could use.")

    # 1. Already linked to this exact provider+subject -> log them in.
    linked = db.execute(
        text("SELECT * FROM find_user_by_oauth(:provider, :subject)"),
        {"provider": provider_name, "subject": subject},
    ).mappings().first()

    if linked:
        user_id, tenant_id = str(linked["id"]), str(linked["tenant_id"])
    else:
        # 2. An account with this email exists under a different
        #    provider (or 'local') -> link this OAuth identity to it
        #    instead of creating a confusing duplicate account.
        by_email = None
        if email:
            by_email = db.execute(
                text("SELECT * FROM find_user_by_email_any_tenant(:email)"), {"email": email}
            ).mappings().first()

        if by_email:
            db.execute(
                text("SELECT link_oauth_identity(:id, :provider, :subject)"),
                {"id": by_email["id"], "provider": provider_name, "subject": subject},
            )
            db.commit()
            user_id, tenant_id = str(by_email["id"]), str(by_email["tenant_id"])
        else:
            # 3. First time we've ever seen this person -> auto-provision
            #    a brand-new tenant for them (rename-able later).
            tenant_row = db.execute(
                text("SELECT create_company_for_admin(:name, :industry) AS id"),
                {"name": f"{display_name}'s workspace", "industry": "unspecified"},
            ).mappings().first()
            tenant_id = str(tenant_row["id"])
            db.execute(text("SELECT seed_default_use_cases_for_tenant(:id)"), {"id": tenant_id})

            user_row = db.execute(
                text("SELECT create_user_for_admin(:tenant_id, :display_name, :email) AS id"),
                {
                    "tenant_id": tenant_id, "display_name": display_name,
                    "email": email or f"{subject}@{provider_name}.oauth",
                },
            ).mappings().first()
            user_id = str(user_row["id"])
            db.execute(
                text("SELECT link_oauth_identity(:id, :provider, :subject)"),
                {"id": user_id, "provider": provider_name, "subject": subject},
            )
            db.commit()

    set_tenant_context(db, tenant_id, user_id)
    db.execute(text("SELECT record_login_success(:id)"), {"id": user_id})
    db.commit()

    token = issue_access_token(user_id=user_id, tenant_id=tenant_id)
    return RedirectResponse(f"{config.FRONTEND_BASE_URL}/?token={token}")
