"""
Dashboard pinning — private by default, whole-dashboard sharing by email.

Every pin is private to the user who made it, UNLESS its owner has
shared their whole dashboard with you (dashboard_shares table) — see
database/dashboard_sharing_by_email.sql. This is a relationship between
two people ("Sarah shared her dashboard with Raj"), not a flag on each
individual pin — sharing one card doesn't exist as a concept here on
purpose, matching the actual requirement.

Row-Level Security enforces this at the database level (not just this
file's own logic): a SELECT on pinned_items returns your own pins PLUS
anyone's pins where they've shared their dashboard with you, while
INSERT/UPDATE/DELETE only ever work on pins you own.
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


class ShareRequest(BaseModel):
    email: str


@router.get("/items")
def list_items(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """RLS does the actual filtering (own pins + anyone who's shared
    their dashboard with you). is_mine is computed from ctx.user_id
    (already known) so the frontend can label "yours" vs "shared by X"
    without a second round trip."""
    rows = db.execute(
        text(
            "SELECT p.id, p.source, p.item_type, p.title, p.payload, p.created_at, "
            "p.user_id, u.display_name AS owner_name "
            "FROM pinned_items p LEFT JOIN users u ON u.id = p.user_id "
            "ORDER BY p.created_at DESC"
        )
    ).mappings().all()
    return [
        {
            "id": str(r["id"]), "source": r["source"], "item_type": r["item_type"],
            "title": r["title"], "payload": r["payload"], "created_at": r["created_at"].isoformat(),
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


@router.get("/shares")
def list_my_shares(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Who you've shared your own dashboard with — for showing/removing
    existing shares in the UI."""
    rows = db.execute(
        text(
            "SELECT ds.id, ds.shared_with_user_id, u.display_name, u.email "
            "FROM dashboard_shares ds JOIN users u ON u.id = ds.shared_with_user_id "
            "WHERE ds.owner_user_id = :me ORDER BY u.display_name"
        ),
        {"me": ctx.user_id},
    ).mappings().all()
    return [dict(r) for r in rows]


@router.post("/shares")
def share_dashboard(
    body: ShareRequest,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Shares your WHOLE dashboard with one person, found by email —
    deliberately restricted to someone who already has a login IN YOUR
    OWN TENANT. Explicitly tenant_id-scoped below (users lives in
    public, not the tenant schema) so someone from a different company
    can never be found or shared with, even by exact email match.
    """
    email = body.email.strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Email is required")

    target = db.execute(
        text("SELECT id, display_name FROM users WHERE tenant_id = :tenant_id AND lower(email) = :email"),
        {"tenant_id": ctx.tenant_id, "email": email},
    ).mappings().first()
    if target is None:
        raise HTTPException(
            status_code=404,
            detail="No user with that email in your organization. They need an existing login to be shared with.",
        )
    if str(target["id"]) == str(ctx.user_id):
        raise HTTPException(status_code=400, detail="You can't share your dashboard with yourself.")

    db.execute(
        text(
            "INSERT INTO dashboard_shares (tenant_id, owner_user_id, shared_with_user_id) "
            "VALUES (:tenant_id, :owner, :recipient) "
            "ON CONFLICT (owner_user_id, shared_with_user_id) DO NOTHING"
        ),
        {"tenant_id": ctx.tenant_id, "owner": ctx.user_id, "recipient": str(target["id"])},
    )
    db.commit()
    return {"shared_with": target["display_name"]}


@router.delete("/shares/{share_id}")
def unshare_dashboard(
    share_id: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """RLS's owner-only write policy on dashboard_shares already
    guarantees this can only remove a share YOU created."""
    result = db.execute(text("DELETE FROM dashboard_shares WHERE id = :id"), {"id": share_id})
    db.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Share not found")
    return {"deleted": True}
