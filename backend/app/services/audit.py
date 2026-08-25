"""
Audit Logging
==============
Writes a durable record of meaningful events (logins, questions asked,
guardrail decisions) to the audit_log table, tagged by tenant.

IMPORTANT: this commits immediately, rather than waiting for the rest of
the request to finish. That is deliberate: an audit trail should record
that something was attempted even if something else in the request
fails afterward.

Every caller of log_event() must have already established tenant context
on this database session (via set_tenant_context) -- for protected
endpoints that is already done by get_current_user; for the login
endpoint itself, main.py sets it explicitly right after resolving the
tenant, before logging the login event. Row-Level Security means an
insert without a matching tenant context would simply fail, so this
isn't optional -- it is enforced by the database, not just a convention.
"""
import json
from sqlalchemy.orm import Session
from sqlalchemy import text


def log_event(db: Session, tenant_id: str, user_id, action: str, details: dict) -> None:
    # Defensive: re-assert tenant context right here, immediately before
    # writing, rather than trusting that it's still correctly set from
    # earlier in the request. tenant_id is already a required, verified
    # parameter here, so this costs nothing and removes any dependence on
    # ambient session state that could (in principle, under connection
    # pooling/threading) have been cleared or changed since this request
    # started.
    db.execute(text("SET app.current_tenant_id = :tenant_id"), {"tenant_id": tenant_id})
    db.execute(
        text(
            "INSERT INTO audit_log (tenant_id, user_id, action, details) "
            "VALUES (:tenant_id, :user_id, :action, CAST(:details AS JSONB))"
        ),
        {
            "tenant_id": tenant_id,
            "user_id": user_id,
            "action": action,
            "details": json.dumps(details, default=str),
        },
    )
    db.commit()
