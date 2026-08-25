"""
==============================================================================
TEMPORARY — FAKE LOGIN FOR LOCAL TESTING ONLY
==============================================================================
This file exists because we do not have a real Microsoft Entra ID App
Registration yet. It lets us build and test everything else (tenant
resolution, RBAC, multi-tenant isolation) without waiting on Azure access.

WHAT THIS IS NOT: this is not secure, is not meant for production, and
issues a token signed with a throwaway local secret (see .env.example).

WHEN REAL ENTRA ID IS READY: this file gets deleted. Nothing else in the
app needs to change, because everything downstream (dependencies.py) only
ever asks "who is this user and what tenant/roles do they have" — it does
not care HOW that was proven. Swapping this file for real Entra ID
validation is the entire migration.
==============================================================================
"""
from datetime import datetime, timedelta, timezone
from jose import jwt

from app.config import FAKE_AUTH_SECRET

ALGORITHM = "HS256"
TOKEN_LIFETIME_MINUTES = 60


def issue_fake_token(user_id: str, tenant_id: str) -> str:
    """
    Creates a signed token containing the user's ID and tenant ID —
    imitating the shape of what a real Entra ID token would eventually
    provide (it also contains a subject and tenant claim, just signed by
    Microsoft instead of by us).
    """
    payload = {
        "sub": user_id,           # "subject" = who this token is about
        "tenant_id": tenant_id,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=TOKEN_LIFETIME_MINUTES),
        "iss": "ryze-infinity-fake-auth",   # clearly marked as non-production
    }
    return jwt.encode(payload, FAKE_AUTH_SECRET, algorithm=ALGORITHM)


def decode_fake_token(token: str) -> dict:
    """Verifies the token's signature and expiry, returns its contents."""
    return jwt.decode(token, FAKE_AUTH_SECRET, algorithms=[ALGORITHM])
