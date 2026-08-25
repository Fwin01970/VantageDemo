"""
Governance
===========
Read/decision surface for the guardrail proxy layer that sits between
this app and any LLM/Databricks call (guardrails/engine.py +
llm_classifier.py, invoked from chat.py before anything is answered or
queried). Two things live here:

  1. A recent-activity feed of guardrail decisions (blocks, flags) —
     pulled from audit_log, since every guardrail decision already gets
     logged there via log_event(). This endpoint doesn't duplicate that
     data anywhere; it's just a tenant-scoped, governance-relevant view
     of it, filtered to the guardrail-related action names.
  2. The HITL (human-in-the-loop) queue — borderline cases that weren't
     confidently allowed OR confidently blocked, and need an actual
     person to decide. See services/governance_queue.py and
     add_governance_hitl.sql for how a case ends up here.

Viewing either requires 'audit:view'. Deciding a HITL case requires the
separate 'governance:manage' permission — reviewing is a decision with
downstream consequences, not just visibility.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.services.tenant_resolver import TenantContext
from app.services.rbac import require_permission
from app.services import governance_queue as hitl
from app.services.audit import log_event

router = APIRouter(prefix="/governance", tags=["governance"])

# Action names written by guardrail decisions elsewhere in the app
# (chat.py, and the Genie path if/when it logs the same way) — kept as an
# explicit allowlist here rather than "everything in audit_log" so this
# feed stays focused on guardrail/governance events specifically, not
# every audit entry (logins, pins, credential changes, etc.).
GUARDRAIL_ACTIONS = (
    "chat.message.blocked",
    "chat.message.hitl_flagged",
    "chat.llm_guardrail_unavailable",
    "chat.llm_unavailable",
)


class DecisionRequest(BaseModel):
    decision: str  # "approved" | "rejected"
    note: str | None = None


@router.get("/activity")
def get_guardrail_activity(
    ctx: TenantContext = Depends(require_permission("audit:view")),
    db: Session = Depends(get_db),
    limit: int = 100,
):
    placeholders = ", ".join(f":a{i}" for i in range(len(GUARDRAIL_ACTIONS)))
    params = {f"a{i}": action for i, action in enumerate(GUARDRAIL_ACTIONS)}
    params["limit"] = min(limit, 200)
    rows = db.execute(
        text(
            f"SELECT id, user_id, action, details, created_at FROM audit_log "
            f"WHERE action IN ({placeholders}) ORDER BY created_at DESC LIMIT :limit"
        ),
        params,
    ).mappings().all()
    return [dict(r) for r in rows]


@router.get("/hitl")
def list_hitl_queue(
    ctx: TenantContext = Depends(require_permission("audit:view")),
    db: Session = Depends(get_db),
    status: str | None = None,
):
    return hitl.list_reviews(db, status=status)


@router.post("/hitl/{review_id}/decision")
def decide_hitl_case(
    review_id: str,
    body: DecisionRequest,
    ctx: TenantContext = Depends(require_permission("governance:manage")),
    db: Session = Depends(get_db),
):
    if body.decision not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail="decision must be 'approved' or 'rejected'")

    result = hitl.decide_review(db, review_id, ctx.user_id, body.decision, body.note)
    if result is None:
        raise HTTPException(status_code=404, detail="No pending review found with that id")

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="governance.hitl_decision",
        details={"review_id": review_id, "decision": body.decision, "note": body.note},
    )
    return result
