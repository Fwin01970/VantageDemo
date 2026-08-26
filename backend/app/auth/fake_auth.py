"""
==============================================================================
TEMPORARY — DEMO LOGIN FOR LOCAL TESTING ONLY
==============================================================================
This file exists because we do not have a real Microsoft Entra ID App
Registration yet. It lets us build and test everything else (tenant
resolution, RBAC, multi-tenant isolation) without waiting on Azure access.

Token issuance itself now lives in auth/tokens.py, shared with real
email/password login and OAuth (routers/auth.py) — so a token looks and
behaves identically no matter how someone signed in. This file is just
the demo-user-picker convenience layer on top of that shared issuer.

WHEN REAL ENTRA ID IS READY: this file gets deleted. Nothing else in the
app needs to change, because everything downstream (dependencies.py) only
ever asks "who is this user and what tenant/roles do they have" — it does
not care HOW that was proven.
==============================================================================
"""
from app.auth.tokens import issue_access_token, decode_access_token

# Kept as thin aliases so existing imports (main.py, dependencies.py)
# don't need to change — the actual implementation is now shared.
issue_fake_token = issue_access_token
decode_fake_token = decode_access_token
