"""
Governance
===========
Read/decision surface for the guardrail proxy layer that sits between
this app and any LLM/Databricks call (guardrails/engine.py +
llm_classifier.py, invoked from chat.py before anything is answered or
queried). Three things live here:

  1. A recent-activity feed of guardrail decisions (blocks, flags) —
     pulled from audit_log, since every guardrail decision already gets
     logged there via log_event(). This endpoint doesn't duplicate that
     data anywhere; it's just a tenant-scoped, governance-relevant view
     of it, filtered to the guardrail-related action names.
  2. The HITL (human-in-the-loop) queue — borderline cases that weren't
     confidently allowed OR confidently blocked, and need an actual
     person to decide. See services/governance_queue.py and
     add_governance_hitl.sql for how a case ends up here. Supports a
     third "hold" outcome alongside approve/reject, and can be filtered
     to one user's own history.
  3. A safe, high-level summary of which guardrail categories are
     active — counts and descriptions only, NEVER the actual detection
     patterns themselves (exposing those would help someone craft text
     specifically designed to slip past them).

Viewing requires 'audit:view'. Deciding a HITL case requires the
separate 'governance:manage' permission — reviewing is a decision with
downstream consequences, not just visibility.

The raw platform-wide Audit Log itself is intentionally NOT exposed
here anymore — that's Platform Admin-only now (routers/admin.py's
/admin/audit-log), not something an ordinary tenant user sees in their
own Governance panel.
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
from app.guardrails.engine import PII_PATTERNS, JB_PATTERNS, FAIRNESS_PATTERNS

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

VALID_DECISIONS = ("approved", "rejected", "hold")


class DecisionRequest(BaseModel):
    decision: str  # "approved" | "rejected" | "hold"
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


@router.get("/guardrails-info")
def get_guardrails_info(
    ctx: TenantContext = Depends(require_permission("audit:view")),
):
    """
    A safe, high-level answer to "which guardrails are actually running
    on my questions?" — deliberately reports category names, counts, and
    plain-language descriptions only. NEVER returns the actual regex
    patterns from guardrails/engine.py: showing someone exactly which
    phrasings trigger jailbreak detection would hand them a recipe for
    evading it, which defeats the entire point of this feature existing.
    """
    return [
        {
            "name": "Jailbreak / prompt-injection detection",
            "stage": "before your question is sent to the AI",
            "description": "Blocks attempts to make the AI ignore its safety rules or pretend to be unrestricted.",
            "pattern_count": len(JB_PATTERNS),
        },
        {
            "name": "Personally Identifiable Information (PII) masking",
            "stage": "before your question is sent to the AI",
            "description": "Automatically masks things like SSNs, emails, phone numbers, and card numbers in your question before the AI ever sees them — the question still gets answered, just without the sensitive detail.",
            "pattern_count": len(PII_PATTERNS),
        },
        {
            "name": "Fairness / discriminatory-pattern detection",
            "stage": "before your question is sent to the AI",
            "description": "Blocks questions that ask for decisions based on protected characteristics instead of legitimate business criteria.",
            "pattern_count": len(FAIRNESS_PATTERNS),
        },
        {
            "name": "Off-topic / scope detection",
            "stage": "before your question is sent to the AI (second-pass AI check)",
            "description": "A second, smarter check catches reworded attempts at the above, and questions unrelated to your company's business data.",
        },
        {
            "name": "Output grounding",
            "stage": "after the AI answers, before you see the result",
            "description": "Checks that every number in the AI's answer actually appears in the real data returned — flags it if the AI invented a figure.",
        },
    ]


@router.get("/hitl")
def list_hitl_queue(
    ctx: TenantContext = Depends(require_permission("audit:view")),
    db: Session = Depends(get_db),
    status: str | None = None,
    user_id: str | None = None,
):
    return hitl.list_reviews(db, status=status, user_id=user_id)


@router.post("/hitl/{review_id}/decision")
def decide_hitl_case(
    review_id: str,
    body: DecisionRequest,
    ctx: TenantContext = Depends(require_permission("governance:manage")),
    db: Session = Depends(get_db),
):
    if body.decision not in VALID_DECISIONS:
        raise HTTPException(status_code=400, detail=f"decision must be one of {VALID_DECISIONS}")

    result = hitl.decide_review(db, review_id, ctx.user_id, body.decision, body.note)
    if result is None:
        raise HTTPException(status_code=404, detail="No pending or held review found with that id")

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="governance.hitl_decision",
        details={"review_id": review_id, "decision": body.decision, "note": body.note},
    )
    return result
