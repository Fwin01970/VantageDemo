"""
Generic OAuth2/OIDC provider registry.

Each provider below is a COMPLETE definition of its flow — the actual
authorize/callback logic in routers/auth.py is written once and works
against any of them. A provider only becomes usable once its client
id/secret are set in .env (see config.py); until then, get_provider()
still returns its definition (so /auth/providers can report it exists)
but is_configured() is False and the frontend won't show a button for it.

Adding a fifth provider later means adding one entry here — no changes
needed anywhere else.
"""
from dataclasses import dataclass
from typing import Optional

from app import config


@dataclass
class OAuthProvider:
    name: str
    display_name: str
    authorize_url: str
    token_url: str
    userinfo_url: str
    scope: str
    client_id: Optional[str]
    client_secret: Optional[str]
    # GitHub in particular often doesn't return a verified email on the
    # main userinfo endpoint — this lets a provider specify a second
    # call to make if the first one comes back without an email.
    email_fallback_url: Optional[str] = None

    def is_configured(self) -> bool:
        return bool(self.client_id and self.client_secret)


def _microsoft() -> OAuthProvider:
    tenant = config.MICROSOFT_TENANT
    return OAuthProvider(
        name="microsoft",
        display_name="Microsoft",
        authorize_url=f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize",
        token_url=f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
        userinfo_url="https://graph.microsoft.com/oidc/userinfo",
        scope="openid profile email",
        client_id=config.MICROSOFT_CLIENT_ID,
        client_secret=config.MICROSOFT_CLIENT_SECRET,
    )


def _google() -> OAuthProvider:
    return OAuthProvider(
        name="google",
        display_name="Google",
        authorize_url="https://accounts.google.com/o/oauth2/v2/auth",
        token_url="https://oauth2.googleapis.com/token",
        userinfo_url="https://openidconnect.googleapis.com/v1/userinfo",
        scope="openid email profile",
        client_id=config.GOOGLE_CLIENT_ID,
        client_secret=config.GOOGLE_CLIENT_SECRET,
    )


def _github() -> OAuthProvider:
    return OAuthProvider(
        name="github",
        display_name="GitHub",
        authorize_url="https://github.com/login/oauth/authorize",
        token_url="https://github.com/login/oauth/access_token",
        userinfo_url="https://api.github.com/user",
        email_fallback_url="https://api.github.com/user/emails",
        scope="read:user user:email",
        client_id=config.GITHUB_CLIENT_ID,
        client_secret=config.GITHUB_CLIENT_SECRET,
    )


def _facebook() -> OAuthProvider:
    return OAuthProvider(
        name="facebook",
        display_name="Facebook",
        authorize_url="https://www.facebook.com/v19.0/dialog/oauth",
        token_url="https://graph.facebook.com/v19.0/oauth/access_token",
        userinfo_url="https://graph.facebook.com/me?fields=id,name,email",
        scope="email public_profile",
        client_id=config.FACEBOOK_CLIENT_ID,
        client_secret=config.FACEBOOK_CLIENT_SECRET,
    )


_REGISTRY = {"microsoft": _microsoft, "google": _google, "github": _github, "facebook": _facebook}


def get_provider(name: str) -> Optional[OAuthProvider]:
    factory = _REGISTRY.get(name)
    return factory() if factory else None


def all_providers() -> list[OAuthProvider]:
    return [factory() for factory in _REGISTRY.values()]


def extract_identity(provider_name: str, userinfo: dict, fallback_emails: list[dict] | None = None) -> tuple[str, str | None, str]:
    """Returns (subject, email, display_name) from a provider's raw
    userinfo response — each provider shapes this data differently."""
    if provider_name == "microsoft":
        return (
            userinfo.get("sub", ""),
            userinfo.get("email") or userinfo.get("preferred_username"),
            userinfo.get("name", "Unknown"),
        )
    if provider_name == "google":
        return (userinfo.get("sub", ""), userinfo.get("email"), userinfo.get("name", "Unknown"))
    if provider_name == "github":
        email = userinfo.get("email")
        if not email and fallback_emails:
            primary = next((e for e in fallback_emails if e.get("primary")), None)
            email = (primary or (fallback_emails[0] if fallback_emails else {})).get("email")
        return (str(userinfo.get("id", "")), email, userinfo.get("name") or userinfo.get("login", "Unknown"))
    if provider_name == "facebook":
        return (userinfo.get("id", ""), userinfo.get("email"), userinfo.get("name", "Unknown"))
    return ("", None, "Unknown")
