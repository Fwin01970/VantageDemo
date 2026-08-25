"""
Conversation persistence — chat history survives page refresh, and is
listed per-user in the conversation sidebar. RLS scopes conversations by
tenant automatically; the tenant_id passed in here must already be
verified (comes from the logged-in user's TenantContext).
"""
from sqlalchemy.orm import Session
from sqlalchemy import text
import json


def create_conversation(db: Session, tenant_id: str, user_id: str, title: str = "New conversation") -> str:
    # Same defensive re-assertion as log_event — tenant_id is already a
    # trusted parameter here, so we don't rely on ambient session state.
    db.execute(text("SET app.current_tenant_id = :tenant_id"), {"tenant_id": tenant_id})
    row = db.execute(
        text(
            "INSERT INTO chat_conversations (tenant_id, user_id, title) "
            "VALUES (:tenant_id, :user_id, :title) RETURNING id"
        ),
        {"tenant_id": tenant_id, "user_id": user_id, "title": title},
    ).mappings().first()
    db.commit()
    return str(row["id"])


def list_conversations(db: Session, user_id: str) -> list[dict]:
    rows = db.execute(
        text(
            "SELECT id, title, updated_at FROM chat_conversations "
            "WHERE user_id = :user_id ORDER BY updated_at DESC LIMIT 30"
        ),
        {"user_id": user_id},
    ).mappings().all()
    return [dict(r) for r in rows]


def get_messages(db: Session, conversation_id: str) -> list[dict]:
    rows = db.execute(
        text(
            "SELECT role, content, chart_data FROM chat_messages "
            "WHERE conversation_id = :cid ORDER BY created_at ASC"
        ),
        {"cid": conversation_id},
    ).mappings().all()
    return [dict(r) for r in rows]


def append_message(db: Session, conversation_id: str, role: str, content: str, chart_data: dict | None = None) -> None:
    db.execute(
        text(
            "INSERT INTO chat_messages (conversation_id, role, content, chart_data) "
            "VALUES (:cid, :role, :content, CAST(:chart_data AS JSONB))"
        ),
        {
            "cid": conversation_id, "role": role, "content": content,
            "chart_data": json.dumps(chart_data) if chart_data is not None else None,
        },
    )
    db.execute(
        text("UPDATE chat_conversations SET updated_at = now() WHERE id = :cid"),
        {"cid": conversation_id},
    )
    db.commit()


def maybe_set_title(db: Session, conversation_id: str, first_user_message: str) -> None:
    """Titles a fresh conversation from its first message, so the sidebar
    shows something meaningful instead of 'New conversation' forever."""
    title = first_user_message.strip()[:60]
    if len(first_user_message.strip()) > 60:
        title += "…"
    db.execute(
        text(
            "UPDATE chat_conversations SET title = :title "
            "WHERE id = :cid AND title = 'New conversation'"
        ),
        {"title": title, "cid": conversation_id},
    )
    db.commit()
