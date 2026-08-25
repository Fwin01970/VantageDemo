"""
Dashboard pinning — real persistence, scoped per-tenant (and per-user)
via Row-Level Security, same guarantee as everything else in this app.

item_type shapes:
  'insight' -> payload = {"text": "..."}
  'table'   -> payload = {"columns": [...], "rows": [[...], ...]}
  'chart'   -> payload = {"columns": [...], "rows": [[...], ...]} — same
               shape as 'table'; item_type alone tells the dashboard to
               render it as a chart (via ChatDataChart) instead of a table.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text
import json

from app.database import get_db
from app.auth.dependencies import get_current_user
from app.services.tenant_resolver import TenantContext

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


class NewPin(BaseModel):
    source: str        # "ask_ai" | "genie"
    item_type: str     # "insight" | "table" | "chart"
    title: str
    payload: dict


@router.get("/items")
def list_items(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text(
            "SELECT id, source, item_type, title, payload, created_at "
            "FROM pinned_items ORDER BY created_at DESC"
        )
    ).mappings().all()
    return [
        {
            "id": str(r["id"]), "source": r["source"], "item_type": r["item_type"],
            "title": r["title"], "payload": r["payload"], "created_at": r["created_at"].isoformat(),
        }
        for r in rows
    ]


@router.post("/items")
def create_item(
    body: NewPin,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.execute(
        text(
            "INSERT INTO pinned_items (tenant_id, user_id, source, item_type, title, payload) "
            "VALUES (:tenant_id, :user_id, :source, :item_type, :title, CAST(:payload AS JSONB)) "
            "RETURNING id"
        ),
        {
            "tenant_id": ctx.tenant_id, "user_id": ctx.user_id, "source": body.source,
            "item_type": body.item_type, "title": body.title, "payload": json.dumps(body.payload),
        },
    ).mappings().first()
    db.commit()
    return {"id": str(row["id"])}


@router.delete("/items/{item_id}")
def delete_item(
    item_id: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    result = db.execute(text("DELETE FROM pinned_items WHERE id = :id"), {"id": item_id})
    db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"deleted": True}
