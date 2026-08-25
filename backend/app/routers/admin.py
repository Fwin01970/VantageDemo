"""
Platform Admin — create new demo companies and users (testing convenience)
=============================================================================
Gated by 'platform:manage', a permission deliberately SEPARATE from
'tenant:manage'. A Tenant Admin manages their own company; creating brand
new companies is a Platform Super Admin action. Blurring that line would
undermine the whole point of the tenant isolation we built and tested
earlier. In a real deployment, 'platform:manage' would belong to a
dedicated platform-operator account, not an ordinary tenant's admin — it's
granted to a demo user here purely so this is testable locally.

These endpoints use SECURITY DEFINER database functions (see
database/add_platform_admin.sql) to deliberately bypass Row-Level
Security for this one narrow purpose — everywhere else in the app, RLS
still applies exactly as before.
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext
from app.services.audit import log_event

router = APIRouter(prefix="/admin", tags=["platform-admin"])


@router.get("/companies")
def list_companies(
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    """Lists every company on the platform — deliberately cross-tenant,
    unlike every other list endpoint in this app. Used to populate the
    'which company' picker when adding a demo user."""
    rows = db.execute(text("SELECT * FROM list_all_companies_for_admin()")).mappings().all()
    return [dict(r) for r in rows]


class NewCompany(BaseModel):
    name: str
    industry: str


@router.post("/companies")
def create_company(
    body: NewCompany,
    ctx: TenantContext = Depends(require_permission("platform:manage")),
    db: Session = Depends(get_db),
):
    result = db.execute(
        text("SELECT create_company_for_admin(:name, :industry) AS id"),
        {"name": body.name, "industry": body.industry},
    ).mappings().first()
    new_id = str(result["id"])

    # Loss ratio is a useful baseline metric regardless of industry —
    # every new tenant gets it as a starting preset, not just insurance
    # ones (see add_default_loss_ratio_use_case.sql for the backfill of
    # existing tenants that predate this).
    db.execute(text("SELECT seed_default_use_cases_for_tenant(:id)"), {"id": new_id})
    db.commit()

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.company_created",
        details={"new_tenant_id": new_id, "name": body.name, "industry": body.industry},
    )
    return {"id": new_id, "name": body.name, "industry": body.industry}


class NewUser(BaseModel):
    tenant_id: str
    display_name: str
    email: str


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

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="admin.user_created",
        details={"new_user_id": new_id, "tenant_id": body.tenant_id, "email": body.email},
    )
    return {"id": new_id, "display_name": body.display_name, "email": body.email}
