"""
Dashboard pinning — private by default, shareable on request.

Every pin is created private to the user who made it. Row-Level
Security enforces this at the database level, not just in this file's
own logic (see database/private_dashboards.sql): a SELECT returns your
own pins PLUS anyone's pins that have been explicitly shared, while
INSERT/UPDATE/DELETE only ever work on pins you own — a user who can
see someone else's shared pin still can't unshare, edit, or delete it.

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
    source: str        # "ask_ai" | "genie" | "use_case"
    item_type: str     # "insight" | "table" | "chart"
    title: str
    payload: dict


@router.get("/items")
def list_items(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    RLS already does the actual filtering here (own pins + anyone's
    shared pins) — this query is intentionally unqualified beyond that.
    is_owned_by_me is computed in Python from the already-known ctx.user_id
    rather than trusting is_shared alone, so the frontend can distinguish
    "my private pin", "my shared pin", and "someone else's shared pin"
    without a second round trip.
    """
    rows = db.execute(
        text(
            "SELECT p.id, p.source, p.item_type, p.title, p.payload, p.created_at, "
            "p.is_shared, p.user_id, u.display_name AS owner_name "
            "FROM pinned_items p LEFT JOIN users u ON u.id = p.user_id "
            "ORDER BY p.created_at DESC"
        )
    ).mappings().all()
    return [
        {
            "id": str(r["id"]), "source": r["source"], "item_type": r["item_type"],
            "title": r["title"], "payload": r["payload"], "created_at": r["created_at"].isoformat(),
            "is_shared": r["is_shared"],
            "is_mine": str(r["user_id"]) == str(ctx.user_id),
            "owner_name": r["owner_name"],
        }
        for r in rows
    ]


@router.post("/items")
def create_item(
    body: NewPin,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Always created private (is_shared defaults to false) — sharing is
    a deliberate, separate action via /items/{id}/share, never implicit
    at creation time."""
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


def _set_shared(item_id: str, shared: bool, db: Session) -> dict:
    # No explicit ownership check needed in this query — RLS's
    # owner-only write policy already guarantees this UPDATE can only
    # ever match a row the caller owns, even if they somehow guessed
    # another user's pin id.
    result = db.execute(
        text("UPDATE pinned_items SET is_shared = :shared WHERE id = :id"),
        {"shared": shared, "id": item_id},
    )
    db.commit()
    if result.rowcount == 0:
        # Deliberately the same 404 whether the id doesn't exist at all
        # OR it exists but belongs to someone else — confirming "that
        # pin exists, it's just not yours" would leak information about
        # another user's private data.
        raise HTTPException(status_code=404, detail="Item not found")
    return {"id": item_id, "is_shared": shared}


@router.put("/items/{item_id}/share")
def share_item(item_id: str, ctx: TenantContext = Depends(get_current_user), db: Session = Depends(get_db)):
    return _set_shared(item_id, True, db)


@router.put("/items/{item_id}/unshare")
def unshare_item(item_id: str, ctx: TenantContext = Depends(get_current_user), db: Session = Depends(get_db)):
    return _set_shared(item_id, False, db)


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
