"""
Platform Admin — tenants, users, roles, audit logs, query parameters
=============================================================================
Gated by 'platform:manage', a permission deliberately SEPARATE from
'tenant:manage'. This router manages PLATFORM STRUCTURE ONLY: who exists,
what they're allowed to do, and what each tenant connects to. It does not
touch Ask AI, Genie, or Use Cases — those are product features with their
own routers/permissions and have no place here.

'platform:manage' lives on a dedicated internal "Ryze Infinity (Platform)"
tenant (see database/add_platform_admin.sql), not on any real customer
tenant.

Every SELECT/INSERT/UPDATE/DELETE below goes through a SECURITY DEFINER
database function (database/add_platform_admin.sql,
database/add_admin_extended.sql) that deliberately bypasses Row-Level
Security for this one narrow purpose — everywhere else in the app, RLS
still applies exactly as before. Every function is called only AFTER
require_permission("platform:manage") has already passed in Python.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import text
import json
import secrets

from app.database import get_db
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext
from app.services.audit import log_event
from app.auth.password import hash_password

router = APIRouter(prefix="/admin", tags=["platform-admin"])

PLATFORM_TENANT_ID = "00000000-0000-0000-0000-000000000000"


def _strip(v):
    # Same lesson as CREDENTIAL_MANAGEMENT_DESIGN.md's trailing-whitespace
    # bug (HANDOFF_CREDENTIALS.md item 3) — strip every free-text admin
    # field at the API boundary, so a pasted email or name with invisible
    # trailing spaces can't cause a silent mismatch later (e.g. at login).
    return v.strip() if isinstance(v, str) else v


# ============================================================================
# Tenants (companies)
# ============================================================================

@router.get("/companies")
def list_companies(
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    rows = db.execute(text("SELECT * FROM list_all_companies_for_admin()")).mappings().all()
    return [dict(r) for r in rows]


class NewCompany(BaseModel):
    name: str
    industry: str
    _strip_fields = field_validator("name", "industry")(_strip)


@router.post("/companies")
def create_company(
    body: NewCompany,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """
    Creates a tenant only. Deliberately does NOT seed Use Cases, Ask AI
    conversations, or any other product content — this is platform
    structure, not product data. A new tenant starts genuinely empty;
    populating it with use cases/dashboards is that tab's own job, not
    Admin's.
    """
    result = db.execute(
        text("SELECT create_company_for_admin(:name, :industry) AS id"),
        {"name": body.name, "industry": body.industry},
    ).mappings().first()
    new_id = str(result["id"])
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.company_created",
        details={"new_tenant_id": new_id, "name": body.name, "industry": body.industry},
    )
    return {"id": new_id, "name": body.name, "industry": body.industry}


class UpdateCompany(BaseModel):
    name: str
    industry: str
    _strip_fields = field_validator("name", "industry")(_strip)


@router.put("/companies/{tenant_id}")
def update_company(
    tenant_id: str,
    body: UpdateCompany,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    db.execute(
        text("SELECT update_company_for_admin(:tenant_id, :name, :industry)"),
        {"tenant_id": tenant_id, "name": body.name, "industry": body.industry},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.company_updated",
        details={"tenant_id": tenant_id, "name": body.name, "industry": body.industry},
    )
    return {"id": tenant_id, "name": body.name, "industry": body.industry}


def _set_company_active(tenant_id: str, is_active: bool, ctx: TenantContext, db: Session):
    if tenant_id == PLATFORM_TENANT_ID and not is_active:
        raise HTTPException(status_code=400, detail="Cannot disable the internal platform tenant")
    db.execute(
        text("SELECT set_company_active_for_admin(:tenant_id, :is_active)"),
        {"tenant_id": tenant_id, "is_active": is_active},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.company_disabled" if not is_active else "admin.company_enabled",
        details={"tenant_id": tenant_id},
    )
    return {"id": tenant_id, "is_active": is_active}


@router.put("/companies/{tenant_id}/disable")
def disable_company(
    tenant_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    return _set_company_active(tenant_id, False, ctx, db)


@router.put("/companies/{tenant_id}/enable")
def enable_company(
    tenant_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    return _set_company_active(tenant_id, True, ctx, db)


@router.delete("/companies/{tenant_id}")
def delete_company(
    tenant_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    if tenant_id == PLATFORM_TENANT_ID:
        raise HTTPException(status_code=400, detail="Cannot delete the internal platform tenant")
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.company_deleted", details={"tenant_id": tenant_id},
    )
    db.execute(text("SELECT delete_company_for_admin(:tenant_id)"), {"tenant_id": tenant_id})
    db.commit()
    return {"id": tenant_id, "deleted": True}


# ============================================================================
# Users
# ============================================================================

@router.get("/users")
def list_users(
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    rows = db.execute(text("SELECT * FROM list_all_users_for_admin()")).mappings().all()
    return [dict(r) for r in rows]


class NewUser(BaseModel):
    tenant_id: str
    display_name: str
    email: str
    _strip_fields = field_validator("display_name", "email")(_strip)


@router.post("/users")
def create_user(
    body: NewUser,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    result = db.execute(
        text("SELECT create_user_for_admin(:tenant_id, :display_name, :email) AS id"),
        {"tenant_id": body.tenant_id, "display_name": body.display_name, "email": body.email},
    ).mappings().first()
    new_id = str(result["id"])
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_created",
        details={"new_user_id": new_id, "tenant_id": body.tenant_id, "email": body.email},
    )
    return {"id": new_id, "display_name": body.display_name, "email": body.email}


class UpdateUser(BaseModel):
    display_name: str
    email: str
    _strip_fields = field_validator("display_name", "email")(_strip)


@router.put("/users/{user_id}")
def update_user(
    user_id: str,
    body: UpdateUser,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    db.execute(
        text("SELECT update_user_for_admin(:user_id, :display_name, :email)"),
        {"user_id": user_id, "display_name": body.display_name, "email": body.email},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_updated",
        details={"user_id": user_id, "display_name": body.display_name, "email": body.email},
    )
    return {"id": user_id, "display_name": body.display_name, "email": body.email}


def _set_user_active(user_id: str, is_active: bool, ctx: TenantContext, db: Session):
    if user_id == ctx.user_id and not is_active:
        raise HTTPException(status_code=400, detail="Cannot disable your own account")
    db.execute(
        text("SELECT set_user_active_for_admin(:user_id, :is_active)"),
        {"user_id": user_id, "is_active": is_active},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_disabled" if not is_active else "admin.user_enabled",
        details={"user_id": user_id},
    )
    return {"id": user_id, "is_active": is_active}


@router.put("/users/{user_id}/disable")
def disable_user(
    user_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    return _set_user_active(user_id, False, ctx, db)


@router.put("/users/{user_id}/enable")
def enable_user(
    user_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    return _set_user_active(user_id, True, ctx, db)


@router.delete("/users/{user_id}")
def delete_user(
    user_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    if user_id == ctx.user_id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_deleted", details={"user_id": user_id},
    )
    db.execute(text("SELECT delete_user_for_admin(:user_id)"), {"user_id": user_id})
    db.commit()
    return {"id": user_id, "deleted": True}


@router.post("/users/{user_id}/reset-password")
def reset_password(
    user_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    temp_password = secrets.token_urlsafe(12)
    db.execute(
        text("SELECT set_user_password_for_admin(:user_id, :password_hash)"),
        {"user_id": user_id, "password_hash": hash_password(temp_password)},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_password_reset", details={"user_id": user_id},
        # the temp password itself is deliberately never written to the
        # audit log — it should prove a reset happened, not become a
        # second place a credential could leak from.
    )
    return {"id": user_id, "temporary_password": temp_password}


# ============================================================================
# Roles
# ============================================================================

@router.get("/tenants/{tenant_id}/roles")
def list_roles(
    tenant_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text("SELECT * FROM list_roles_for_admin(:tenant_id)"), {"tenant_id": tenant_id}
    ).mappings().all()
    return [dict(r) for r in rows]


@router.get("/permissions")
def list_permissions(
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """The full, fixed catalog of permission codes every role picks from —
    e.g. 'data:query', 'genie:access', 'tenant:manage'. Shown as a
    checklist in the role-editing UI."""
    rows = db.execute(text("SELECT * FROM list_all_permissions_for_admin()")).mappings().all()
    return [dict(r) for r in rows]


class NewRole(BaseModel):
    name: str
    description: Optional[str] = None
    permission_codes: list[str] = []
    _strip_fields = field_validator("name")(_strip)


@router.post("/tenants/{tenant_id}/roles")
def create_role(
    tenant_id: str,
    body: NewRole,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    result = db.execute(
        text("SELECT create_role_for_admin(:tenant_id, :name, :description) AS id"),
        {"tenant_id": tenant_id, "name": body.name, "description": body.description},
    ).mappings().first()
    role_id = str(result["id"])

    if body.permission_codes:
        db.execute(
            text("SELECT set_role_permissions_for_admin(:role_id, :codes)"),
            {"role_id": role_id, "codes": body.permission_codes},
        )
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.role_created",
        details={"role_id": role_id, "tenant_id": tenant_id, "name": body.name,
                  "permission_codes": body.permission_codes},
    )
    return {"id": role_id, "name": body.name, "permission_codes": body.permission_codes}


class UpdateRole(BaseModel):
    name: str
    description: Optional[str] = None
    permission_codes: list[str] = []
    _strip_fields = field_validator("name")(_strip)


@router.put("/roles/{role_id}")
def update_role(
    role_id: str,
    body: UpdateRole,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    db.execute(
        text("SELECT update_role_for_admin(:role_id, :name, :description)"),
        {"role_id": role_id, "name": body.name, "description": body.description},
    )
    db.execute(
        text("SELECT set_role_permissions_for_admin(:role_id, :codes)"),
        {"role_id": role_id, "codes": body.permission_codes},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.role_updated",
        details={"role_id": role_id, "name": body.name, "permission_codes": body.permission_codes},
    )
    return {"id": role_id, "name": body.name, "permission_codes": body.permission_codes}


@router.delete("/roles/{role_id}")
def delete_role(
    role_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.role_deleted", details={"role_id": role_id},
    )
    db.execute(text("SELECT delete_role_for_admin(:role_id)"), {"role_id": role_id})
    db.commit()
    return {"id": role_id, "deleted": True}


@router.get("/users/{user_id}/roles")
def list_user_roles(
    user_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text("SELECT * FROM list_roles_for_user_for_admin(:user_id)"), {"user_id": user_id}
    ).mappings().all()
    return [dict(r) for r in rows]


@router.post("/users/{user_id}/roles/{role_id}")
def assign_role(
    user_id: str,
    role_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    db.execute(
        text("SELECT assign_role_to_user_for_admin(:user_id, :role_id)"),
        {"user_id": user_id, "role_id": role_id},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.role_assigned", details={"user_id": user_id, "role_id": role_id},
    )
    return {"user_id": user_id, "role_id": role_id, "assigned": True}


@router.delete("/users/{user_id}/roles/{role_id}")
def remove_role(
    user_id: str,
    role_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    db.execute(
        text("SELECT remove_role_from_user_for_admin(:user_id, :role_id)"),
        {"user_id": user_id, "role_id": role_id},
    )
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.role_removed", details={"user_id": user_id, "role_id": role_id},
    )
    return {"user_id": user_id, "role_id": role_id, "assigned": False}


# ============================================================================
# Query Parameters — per-tenant shared data source connection
# (host / warehouse / catalog / secret reference for Databricks etc.)
# ============================================================================

@router.get("/tenants/{tenant_id}/query-parameters")
def get_query_parameters(
    tenant_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text("SELECT * FROM get_data_source_connection_for_admin(:tenant_id)"),
        {"tenant_id": tenant_id},
    ).mappings().all()
    return [dict(r) for r in rows]


class QueryParameters(BaseModel):
    platform: str                  # 'databricks' | 'local_demo' | ...
    host: Optional[str] = None
    warehouse_id: Optional[str] = None
    catalog: Optional[str] = None
    schema_name: Optional[str] = None
    secret_ref: Optional[str] = None   # points to an env var / secret store key — never the raw secret itself
    is_active: bool = True
    _strip_fields = field_validator("platform", "host", "warehouse_id", "catalog", "schema_name", "secret_ref")(_strip)


@router.put("/tenants/{tenant_id}/query-parameters")
def upsert_query_parameters(
    tenant_id: str,
    body: QueryParameters,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """
    Adds a new connection for this tenant+platform, or edits the existing
    one if it's already there — same endpoint handles both "add" and
    "edit", matching how the admin UI's single save button should work.
    Only non-secret connection details go through this endpoint (host,
    warehouse, catalog); secret_ref is a POINTER to wherever the actual
    credential lives, never the credential itself — same principle
    already established for user_credentials in
    CREDENTIAL_MANAGEMENT_DESIGN.md.
    """
    config = {
        "host": body.host,
        "warehouse_id": body.warehouse_id,
        "catalog": body.catalog,
        "schema": body.schema_name,
    }
    result = db.execute(
        text(
            "SELECT upsert_data_source_connection_for_admin("
            ":tenant_id, :platform, CAST(:config AS JSONB), :secret_ref, :is_active"
            ") AS id"
        ),
        {
            "tenant_id": tenant_id, "platform": body.platform,
            "config": json.dumps(config), "secret_ref": body.secret_ref,
            "is_active": body.is_active,
        },
    ).mappings().first()
    connection_id = str(result["id"])
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.query_parameters_saved",
        details={"tenant_id": tenant_id, "connection_id": connection_id,
                  "platform": body.platform, "config": config},
        # secret_ref (a pointer, not a secret) is fine to log; the actual
        # credential it points to is never present in this endpoint at all.
    )
    return {"id": connection_id, "platform": body.platform, "config": config, "is_active": body.is_active}


@router.delete("/query-parameters/{connection_id}")
def delete_query_parameters(
    connection_id: str,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.query_parameters_deleted", details={"connection_id": connection_id},
    )
    db.execute(
        text("SELECT delete_data_source_connection_for_admin(:connection_id)"),
        {"connection_id": connection_id},
    )
    db.commit()
    return {"id": connection_id, "deleted": True}


# ============================================================================
# Genie dynamic configuration — query parameters, question template,
# suggested questions (per tenant, with optional per-user override)
# ============================================================================
# This is what replaces GeniePage.tsx's old hardcoded PRODUCT_LINES /
# REGIONS / FOCUS_AREAS constants and its "claims and loss ratio"
# template — a tenant in a domain with no concept of "claims" at all
# (retail, banking, whatever) gets its OWN vocabulary here, set by a
# Platform Super Admin, never baked into the frontend.
#
# user_id is optional on every endpoint below: omit it (or pass null) to
# manage the TENANT-WIDE default; pass a specific user_id to give that
# one person their own override. GET /data/genie-config (databricks.py)
# is what an ordinary logged-in user actually sees at runtime — it tries
# their personal override first, then falls back to the tenant default.

class GenieField(BaseModel):
    field_name: str
    options: list[str]
    _strip_fields = field_validator("field_name")(_strip)


class GenieConfigInput(BaseModel):
    user_id: Optional[str] = None  # None = tenant-wide default
    fields: list[GenieField]
    template: str
    suggested_questions: list[str] = []
    _strip_fields = field_validator("template")(_strip)


@router.get("/tenants/{tenant_id}/genie-config")
def get_genie_config_admin(
    tenant_id: str,
    user_id: Optional[str] = None,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """Pass ?user_id=... to view a specific person's override; omit it to
    view the tenant-wide default."""
    row = db.execute(
        text("SELECT * FROM get_genie_config_for_admin(:tenant_id, :user_id)"),
        {"tenant_id": tenant_id, "user_id": user_id},
    ).mappings().first()
    return {
        "fields": row["fields"] if row else [],
        "template": row["template"] if row else None,
        "suggested_questions": row["suggested_questions"] if row else [],
    }


@router.put("/tenants/{tenant_id}/genie-config")
def set_genie_config_admin(
    tenant_id: str,
    body: GenieConfigInput,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """
    Saves fields + template + suggested questions in one call — every
    save fully REPLACES the previous set for this exact scope
    (tenant-wide default, or one user's override), so what's shown in
    the admin UI is always exactly what gets persisted, with nothing
    left over from a previous save.
    """
    fields_json = json.dumps([{"field_name": f.field_name, "options": f.options} for f in body.fields])

    db.execute(
        text("SELECT set_genie_query_parameter_fields_for_admin(:tenant_id, :user_id, CAST(:fields AS JSONB))"),
        {"tenant_id": tenant_id, "user_id": body.user_id, "fields": fields_json},
    )
    db.execute(
        text("SELECT set_genie_question_template_for_admin(:tenant_id, :user_id, :template)"),
        {"tenant_id": tenant_id, "user_id": body.user_id, "template": body.template},
    )
    db.execute(
        text("SELECT set_genie_suggested_questions_for_admin(:tenant_id, :user_id, :questions)"),
        {"tenant_id": tenant_id, "user_id": body.user_id, "questions": body.suggested_questions},
    )
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.genie_config_saved",
        details={
            "tenant_id": tenant_id, "scoped_to_user": body.user_id,
            "field_count": len(body.fields), "suggested_question_count": len(body.suggested_questions),
        },
    )
    return {
        "tenant_id": tenant_id, "user_id": body.user_id,
        "fields": [f.model_dump() for f in body.fields],
        "template": body.template, "suggested_questions": body.suggested_questions,
    }


# ============================================================================
# Audit Log — tenant-wise and user-wise
# ============================================================================

@router.get("/audit-log")
def get_audit_log(
    tenant_id: Optional[str] = None,
    user_id: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """
    Cross-tenant audit feed. Pass tenant_id to see one company's activity,
    add user_id to narrow to one person within it, or pass neither for a
    full platform-wide feed. This is the ONLY place in the app that can
    see audit rows across more than one tenant at once — everywhere else,
    audit_log's normal RLS policy correctly restricts a session to just
    its own tenant.
    """
    limit = max(1, min(limit, 1000))
    rows = db.execute(
        text("SELECT * FROM list_audit_log_for_admin(:tenant_id, :user_id, :limit, :offset)"),
        {"tenant_id": tenant_id, "user_id": user_id, "limit": limit, "offset": offset},
    ).mappings().all()
    return [dict(r) for r in rows]
