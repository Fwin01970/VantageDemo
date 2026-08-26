"""
Shared access-token issuance. fake_auth.py's demo login and the real
auth router (routers/auth.py) both call issue_access_token() so a token
looks and behaves identically no matter how someone signed in — the rest
of the app (auth/dependencies.py) never needs to know or care.
"""
from datetime import datetime, timedelta, timezone
from jose import jwt

from app.config import FAKE_AUTH_SECRET

ALGORITHM = "HS256"
TOKEN_LIFETIME_MINUTES = 60


def issue_access_token(user_id: str, tenant_id: str) -> str:
    payload = {
        "sub": user_id,
        "tenant_id": tenant_id,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=TOKEN_LIFETIME_MINUTES),
        "iss": "ryze-infinity",
    }
    return jwt.encode(payload, FAKE_AUTH_SECRET, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, FAKE_AUTH_SECRET, algorithms=[ALGORITHM])
