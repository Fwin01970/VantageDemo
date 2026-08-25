"""
Use Cases — per-tenant preset analytical starting points.

Nothing about industry is hardcoded here — every row comes from the
use_cases table, scoped to the caller's own tenant via Row-Level
Security. An insurance tenant and a banking tenant see completely
different rows without a single if/else in this file.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.auth.dependencies import get_current_user
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext

router = APIRouter(prefix="/use-cases", tags=["use-cases"])


@router.get("")
def list_use_cases(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text(
            "SELECT id, title, description, category, sample_question, icon_key "
            "FROM use_cases ORDER BY created_at ASC"
        )
    ).mappings().all()
    return [dict(r) | {"id": str(r["id"])} for r in rows]


class NewUseCase(BaseModel):
    title: str
    description: str
    category: str
    sample_question: str
    icon_key: str = "trending-up"


@router.post("")
def create_use_case(
    body: NewUseCase,
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    """
    Creating a new use case is treated as tenant configuration, not
    everyday content — gated by 'tenant:manage' (the same permission
    that already covers managing tenant settings/users/roles), rather
    than introducing yet another new permission for one small action.
    Always inserted against the CALLER'S OWN tenant_id (from their
    verified token, not anything client-supplied), consistent with
    every other tenant-scoped write in this app.
    """
    row = db.execute(
        text(
            "INSERT INTO use_cases (tenant_id, title, description, category, sample_question, icon_key) "
            "VALUES (:tenant_id, :title, :description, :category, :sample_question, :icon_key) "
            "RETURNING id"
        ),
        {
            "tenant_id": ctx.tenant_id, "title": body.title, "description": body.description,
            "category": body.category, "sample_question": body.sample_question, "icon_key": body.icon_key,
        },
    ).mappings().first()
    db.commit()
    return {"id": str(row["id"])}


@router.delete("/{use_case_id}")
def delete_use_case(
    use_case_id: str,
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    """Same permission as creating one — removing a preset use case is
    tenant configuration, not everyday content. RLS on use_cases means
    the DELETE simply matches zero rows if the id belongs to another
    tenant, rather than needing an explicit tenant_id check here."""
    result = db.execute(text("DELETE FROM use_cases WHERE id = :id"), {"id": use_case_id})
    db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="No use case found with that id")
    return {"deleted": True}

