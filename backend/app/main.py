"""
Ryze Infinity — Backend API
============================
Run with:  uvicorn app.main:app --reload
Then open: http://127.0.0.1:8000/docs   (interactive API testing page)

This backend now covers the full app, not just the original bootstrap
skeleton. Endpoints are grouped by router (each shows as its own section
in /docs, from each router's own `tags=[...]`):

  /auth/...              - signup, email+password login, OAuth, demo login
  /me                    - who am I, what tenant, what permissions
  /chat/...              - Ask AI (conversational, with optional real-data tool use)
  /data/...              - Genie (Databricks natural-language-to-SQL) + raw query/discovery
  /use-cases/...         - saved preset questions with cached, re-runnable SQL
  /dashboard/...         - pinned insights/tables/charts
  /credentials/...       - per-user saved Databricks + LLM credentials
  /governance/...        - guardrail activity feed + HITL review queue
  /schema-annotations/...- human-written notes on tables/columns, shown to the AI
  /admin/...             - platform-level: create new demo companies/users
  /admin/tenants         - example RBAC-protected endpoint (legacy bootstrap route)
  /audit/log             - this tenant's own audit trail

See CREDENTIAL_MANAGEMENT_DESIGN.md and RYZE_INFINITY_EXPLAINED.md for the
full walkthrough of how tenant isolation, guardrails, and governance work.
"""
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text, select
import logging
import re

# Without this, our own logger.info(...)/logger.warning(...) calls
# throughout the app (e.g. chat.py's Ask AI diagnostics) never show up
# in the console — Python's root logger has no handler by default, and
# uvicorn only configures its OWN "uvicorn"/"uvicorn.access" loggers,
# not the app's. This is what makes "Ask AI tool call — SQL: ..." and
# similar lines actually appear in the terminal you're watching.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

# httpx logs the full request line (method + URL) at INFO. That's
# harmless for Anthropic/OpenAI (key goes in a header, never in the
# logged part) but Gemini's REST API historically took its key as a
# ?key=... query parameter, which put a live, billable secret in
# plaintext on every single call. providers.py now sends it via header
# instead — but this second, independent layer means a future provider
# (or a mistake) that puts a secret in a URL doesn't silently leak it
# again. WARNING still surfaces httpx-level connection errors.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


class _RedactSecretsFilter(logging.Filter):
    """
    Defense in depth, not the primary fix — the primary fix is "don't put
    secrets where they can be logged" (see providers.py). This exists for
    the case that gets missed: some future header, error body, or
    third-party library log line contains a token/key/password in a
    recognizable position, and this strips it before it reaches any
    handler (console, file, or a shipped-off-box log aggregator) rather
    than relying on every call site remembering to be careful.
    """
    _PATTERNS = [
        (re.compile(r"([?&](?:key|api_key|apikey|token|access_token)=)[^&\s\"']+", re.IGNORECASE), r"\1[REDACTED]"),
        (re.compile(r"(Bearer\s+)[A-Za-z0-9\-_.~+/]+=*", re.IGNORECASE), r"\1[REDACTED]"),
        (re.compile(r"((?:x-api-key|x-goog-api-key)['\"]?\s*[:=]\s*['\"]?)[^'\",\s}]+", re.IGNORECASE), r"\1[REDACTED]"),
    ]

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:
            return True
        redacted = msg
        for pattern, repl in self._PATTERNS:
            redacted = pattern.sub(repl, redacted)
        if redacted != msg:
            record.msg = redacted
            record.args = ()
        return True


logging.getLogger().addFilter(_RedactSecretsFilter())
# Filters attached to a Logger (not a Handler) only run for records
# logged directly to THAT logger — they do NOT run for child loggers
# (httpx, app.routers.chat, etc.) merely propagating up to root's
# handler. Attaching it to the handler itself is what makes it actually
# apply to every log line regardless of which logger produced it.
for _handler in logging.getLogger().handlers:
    _handler.addFilter(_RedactSecretsFilter())

from app.database import get_db, set_tenant_context
from app.models import Tenant
from app.schemas import DemoUserOut, LoginRequest, LoginResponse, MeResponse
from app.auth.fake_auth import issue_fake_token
from app.auth.dependencies import get_current_user
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext
from app.services.audit import log_event
from app.routers.databricks import router as databricks_router
from app.routers.admin import router as admin_router
from app.routers.chat import router as chat_router
from app.routers.use_cases import router as use_cases_router
from app.routers.dashboard import router as dashboard_router
from app.routers.schema_annotations import router as schema_annotations_router
from app.routers.credentials import router as credentials_router
from app.routers.governance import router as governance_router
from app.routers.auth import router as auth_router

app = FastAPI(
    title="Ryze Infinity",
    description=(
        "Multi-tenant business analytics platform — ask plain-English questions "
        "about your company's real data (Ask AI / Genie), backed by guardrails "
        "(jailbreak/PII/fairness/off-topic detection + output grounding), "
        "per-tenant schema isolation, role-based permissions, and a full audit "
        "trail. See RYZE_INFINITY_EXPLAINED.md in the project root for a full "
        "plain-language walkthrough of every endpoint below."
    ),
    version="1.0.0",
)

# The React frontend runs on a different address (localhost:5173) than
# this backend (localhost:8000) — browsers block that kind of
# cross-address request by default unless the server explicitly allows
# it. This is standard for any frontend/backend split, and only allows
# your own local development page to talk to your own local server.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(databricks_router)
app.include_router(admin_router)
app.include_router(chat_router)
app.include_router(use_cases_router)
app.include_router(dashboard_router)
app.include_router(schema_annotations_router)
app.include_router(credentials_router)
app.include_router(governance_router)
app.include_router(auth_router)


@app.get("/health")
def health():
    return {"status": "ok"}


# ── FAKE LOGIN — see app/auth/fake_auth.py for why this exists ─────────
#
# Both endpoints below call database FUNCTIONS (list_demo_users_for_login,
# resolve_login_by_user_id) instead of querying the users table directly.
# This is deliberate: "who is this login and which tenant are they in" is
# a cross-tenant question that has to be answered BEFORE we know which
# tenant to restrict the query to — a normal Row-Level-Security-protected
# query can't do that (see schema.sql for the full explanation). These two
# functions are the one narrow, explicit exception.
@app.get("/auth/demo-users", response_model=list[DemoUserOut])
def list_demo_users(db: Session = Depends(get_db)):
    """
    Lists every demo user across every demo tenant, so the (fake) login
    page can show a 'log in as...' picker. This endpoint itself is also
    temporary — a real login page redirects to Entra ID instead of
    listing users like this.
    """
    rows = db.execute(text("SELECT * FROM list_demo_users_for_login()")).mappings().all()
    return [
        DemoUserOut(
            id=str(r["id"]),
            display_name=r["display_name"],
            email=r["email"],
            tenant_name=r["tenant_name"],
        )
        for r in rows
    ]


@app.post("/auth/demo-login", response_model=LoginResponse)
def fake_login(body: LoginRequest, db: Session = Depends(get_db)):
    row = db.execute(
        text("SELECT * FROM resolve_login_by_user_id(:uid)"),
        {"uid": body.user_id},
    ).mappings().first()

    if row is None or not row["is_active"]:
        raise HTTPException(status_code=404, detail="Demo user not found")

    user_id = str(row["id"])
    tenant_id = str(row["tenant_id"])

    # We now know which tenant AND which user this is — set BOTH before
    # writing the audit row. Row-Level Security requires tenant_id here;
    # user_id is included too for consistency with get_current_user()
    # (see auth/dependencies.py) — leaving it unset in one place and not
    # the other is exactly the kind of gap that silently broke personal
    # credential lookups elsewhere in this app.
    set_tenant_context(db, tenant_id, user_id)
    log_event(db, tenant_id=tenant_id, user_id=user_id, action="auth.login", details={})

    token = issue_fake_token(user_id=user_id, tenant_id=tenant_id)
    return LoginResponse(access_token=token)


# ── Protected endpoints — require a valid token ─────────────────────────
@app.get("/me", response_model=MeResponse)
def me(ctx: TenantContext = Depends(get_current_user)):
    """
    Proves the whole chain works: token -> tenant resolver -> roles ->
    permissions. Log in as different demo users and hit this endpoint to
    see the tenant/permissions change accordingly.
    """
    return MeResponse(
        user_id=ctx.user_id,
        display_name=ctx.display_name,
        email=ctx.email,
        tenant_id=ctx.tenant_id,
        tenant_name=ctx.tenant_name,
        industry=ctx.industry,
        roles=ctx.roles,
        permissions=ctx.permissions,
    )


@app.get("/admin/tenants")
def list_tenants_admin_only(
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    """
    Example RBAC-protected endpoint. Only users whose role grants
    'tenant:manage' can call this — try it as 'Demo Viewer' (who lacks
    this permission) vs 'Sarah Chen' (who has it) to see the 403 in action.

    Because Row-Level Security is active (set in get_current_user), this
    query only ever sees the CALLING USER'S OWN tenant — even though the
    query itself doesn't filter by tenant_id at all. Postgres does it for us.
    """
    tenants = db.execute(select(Tenant)).scalars().all()
    return [{"id": str(t.id), "name": t.name, "industry": t.industry} for t in tenants]


@app.get("/audit/log")
def view_audit_log(
    ctx: TenantContext = Depends(require_permission("audit:view")),
    db: Session = Depends(get_db),
):
    """
    Returns this tenant's own audit entries — Row-Level Security means
    this query physically cannot return another tenant's rows, the same
    guarantee as /admin/tenants. Requires the 'audit:view' permission.
    """
    rows = db.execute(
        text(
            "SELECT id, user_id, action, details, created_at "
            "FROM audit_log ORDER BY created_at DESC LIMIT 100"
        )
    ).mappings().all()
    return [dict(r) for r in rows]
