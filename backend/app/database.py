"""
Sets up the connection to PostgreSQL and provides a per-request database
session. Also provides the helper that tells Postgres "which tenant is this
request for" — this is what makes Row-Level Security (defined in
database/schema.sql) actually kick in.
"""
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session

from app.config import DATABASE_URL

engine = create_engine(DATABASE_URL)


def get_db():
    """
    FastAPI dependency — gives each request its own database session.

    IMPORTANT: this binds the Session to ONE specific, explicitly-checked-
    out Connection for the entire request, rather than binding it to the
    Engine directly. This matters because of a real bug we hit: when a
    Session is bound to the Engine, every db.commit() releases its
    connection back to the pool, and the NEXT query checks out a
    connection again — which, under real concurrent traffic (multiple
    simultaneous requests competing for the pool), is not guaranteed to
    be the same physical connection. Since our tenant context (see
    set_tenant_context below) is set via a Postgres session-level
    variable on ONE physical connection, a request that silently starts
    using a different connection mid-request would lose that context —
    exactly what we observed happening intermittently. Holding one
    Connection for the whole request, and only releasing it back to the
    pool when the request ends, makes this impossible: every query in a
    request always runs on the same physical connection, no matter how
    many times we commit.
    """
    connection = engine.connect()
    db = Session(bind=connection)
    try:
        yield db
    finally:
        try:
            db.rollback()
            connection.execute(text("RESET app.current_tenant_id"))
            connection.execute(text("RESET app.current_user_id"))
            connection.commit()
        except Exception:
            # Connection may already be in a bad state (e.g. the request
            # itself failed with a database error) — don't let cleanup
            # itself raise and mask the original error.
            db.rollback()
        db.close()
        connection.close()


def set_tenant_context(db: Session, tenant_id: str, user_id: str | None = None) -> None:
    """
    Tells Postgres "for the rest of this database session, only show rows
    belonging to this tenant." This is what makes the Row-Level Security
    policies in schema.sql actually take effect — it is a SECOND layer of
    protection underneath our own application-code checks, so a bug in
    Python code alone cannot leak one tenant's rows to another.

    Also optionally sets app.current_user_id — needed for the ONE table
    (user_credentials) whose RLS policy is scoped to a specific user, not
    just their tenant. Every other table only checks tenant_id; this is
    intentionally stricter, since credentials are personal, not shared
    within the company.
    """
    db.execute(text("SET app.current_tenant_id = :tenant_id"), {"tenant_id": tenant_id})
    if user_id:
        db.execute(text("SET app.current_user_id = :user_id"), {"user_id": user_id})
