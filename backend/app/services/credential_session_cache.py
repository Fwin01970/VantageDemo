"""
Session-Only Credential Cache
================================
Backs the "Not Now" path from the credentials flow — see
CREDENTIAL_MANAGEMENT_DESIGN.md §4.4. When a user declines to persist
their credentials, they still need to work for the rest of THIS login
session, but must never touch the database or any secret store.

This is a plain in-process dict, keyed by a hash of the user's JWT (never
the raw token itself, in case this process's memory were ever dumped for
debugging — a hash is enough to look up "this session's" entry without
being usable to reconstruct the token). Entries expire on their own after
a TTL, and are also deleted immediately and explicitly on logout — we
don't rely on the TTL alone for that.

SCALABILITY NOTE (flagged in the design doc, repeating here where it's
actually relevant): this only works correctly with a SINGLE backend
process. The moment this API runs behind a load balancer with more than
one instance, a session-only credential saved on instance A won't be
visible to a request that happens to land on instance B. Moving this to
Redis (or similar) is a prerequisite for horizontal scaling — not
optional, and not done here since this environment has no Redis to
verify it against.
"""
import hashlib
import time

_TTL_SECONDS = 8 * 3600  # matches a typical JWT expiry; adjust alongside token lifetime
_cache: dict[str, tuple[float, dict]] = {}


def _key_for_token(token: str) -> str:
    # SHA-256 of the token, not the token itself — this dict living in
    # process memory should still not be a usable map back to real tokens
    # if it were ever dumped for any reason.
    return hashlib.sha256(token.encode()).hexdigest()


def set_session_credentials(token: str, credentials: dict) -> None:
    """`credentials` should be the plaintext values (PAT, API key, etc.)
    — this is the ONE place in the whole app where a plaintext secret is
    allowed to sit in memory outside of the moment it's actively being
    used, and only for session-only ("Not Now") users who explicitly
    opted out of persistence. Never logged, never serialized to disk."""
    _cache[_key_for_token(token)] = (time.time(), credentials)


def get_session_credentials(token: str) -> dict | None:
    entry = _cache.get(_key_for_token(token))
    if entry is None:
        return None
    stored_at, credentials = entry
    if (time.time() - stored_at) > _TTL_SECONDS:
        _cache.pop(_key_for_token(token), None)
        return None
    return credentials


def clear_session_credentials(token: str) -> None:
    """Call on logout — don't wait for the TTL, remove it immediately."""
    _cache.pop(_key_for_token(token), None)
