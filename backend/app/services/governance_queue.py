"""
Governance HITL Queue
======================
Backing store for borderline guardrail cases that shouldn't be
auto-answered OR auto-blocked with full confidence — they go here for a
human reviewer to actually look at. See add_governance_hitl.sql for the
table and the reasoning behind having this exist at all.
"""
from sqlalchemy.orm import Session
from sqlalchemy import text


def create_review(db: Session, tenant_id: str, user_id: str, question: str, check_type: str, reason: str) -> str:
    row = db.execute(
        text(
            "INSERT INTO governance_reviews (tenant_id, user_id, question, check_type, reason) "
            "VALUES (:tenant_id, :user_id, :question, :check_type, :reason) RETURNING id"
        ),
        {"tenant_id": tenant_id, "user_id": user_id, "question": question, "check_type": check_type, "reason": reason},
    ).mappings().first()
    db.commit()
    return str(row["id"])


def list_reviews(db: Session, status: str | None = None, limit: int = 100) -> list[dict]:
    if status:
        rows = db.execute(
            text(
                "SELECT gr.id, gr.question, gr.check_type, gr.reason, gr.status, gr.created_at, "
                "gr.reviewed_at, gr.decision_note, u.display_name AS user_name, "
                "ru.display_name AS reviewed_by_name "
                "FROM governance_reviews gr "
                "LEFT JOIN users u ON u.id = gr.user_id "
                "LEFT JOIN users ru ON ru.id = gr.reviewed_by "
                "WHERE gr.status = :status ORDER BY gr.created_at DESC LIMIT :limit"
            ),
            {"status": status, "limit": limit},
        ).mappings().all()
    else:
        rows = db.execute(
            text(
                "SELECT gr.id, gr.question, gr.check_type, gr.reason, gr.status, gr.created_at, "
                "gr.reviewed_at, gr.decision_note, u.display_name AS user_name, "
                "ru.display_name AS reviewed_by_name "
                "FROM governance_reviews gr "
                "LEFT JOIN users u ON u.id = gr.user_id "
                "LEFT JOIN users ru ON ru.id = gr.reviewed_by "
                "ORDER BY gr.created_at DESC LIMIT :limit"
            ),
            {"limit": limit},
        ).mappings().all()
    return [dict(r) for r in rows]


def decide_review(db: Session, review_id: str, reviewer_user_id: str, decision: str, note: str | None) -> dict | None:
    """decision must be 'approved' or 'rejected'. Returns the updated row,
    or None if no pending review with this id exists for this tenant (RLS
    already scopes the WHERE-less lookup — a wrong-tenant id simply
    matches zero rows rather than raising)."""
    row = db.execute(
        text(
            "UPDATE governance_reviews SET status = :status, reviewed_by = :reviewer, "
            "reviewed_at = now(), decision_note = :note "
            "WHERE id = :id AND status = 'pending' RETURNING id, status"
        ),
        {"status": decision, "reviewer": reviewer_user_id, "note": note, "id": review_id},
    ).mappings().first()
    db.commit()
    return dict(row) if row else None


def count_pending(db: Session) -> int:
    row = db.execute(text("SELECT count(*) AS c FROM governance_reviews WHERE status = 'pending'")).mappings().first()
    return int(row["c"]) if row else 0
