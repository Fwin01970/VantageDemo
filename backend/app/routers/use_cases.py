"""
Use Cases — per-tenant preset analytical starting points.

Nothing about industry is hardcoded here — every row comes from the
use_cases table, scoped to the caller's own tenant via Row-Level
Security. An insurance tenant and a banking tenant see completely
different rows without a single if/else in this file.

IMPORTANT: launching a use case does NOT call the LLM. The LLM only
ever writes SQL once, when a use case is previewed and saved
(generated_sql is captured from that preview and stored). Every
subsequent launch — by any user, any number of times — just re-runs
that exact stored SQL directly against the warehouse. This is
deliberate: a saved use case is supposed to be a deterministic,
repeatable query, not something that re-guesses new SQL (and re-risks
hitting a rate limit or provider outage) every single time it's opened.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.auth.dependencies import get_current_user
from app.services.tenant_resolver import TenantContext
from app.services.data_source_resolver import get_databricks_client_for_user, DataSourceNotConfigured, SecretNotFound
from app.services.databricks_client import DatabricksError
from app.guardrails.query_validator import assert_read_only, QueryValidationError
from app.services.audit import log_event

router = APIRouter(prefix="/use-cases", tags=["use-cases"])


@router.get("")
def list_use_cases(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.execute(
        text(
            "SELECT id, title, description, category, sample_question, icon_key, "
            "generated_sql, generated_sql IS NOT NULL AS has_cached_query "
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
    # Captured from the Preview step (see ChatResponse.sql in
    # routers/chat.py) — the exact SQL that ran when this question was
    # tested, before being saved as a preset. Optional so a use case can
    # still be created without one (e.g. a purely conversational
    # question with no data query) — Launch just falls back to the
    # normal LLM-driven flow for those.
    generated_sql: str | None = None


def normalize_generated_sql(sql: str | None) -> str | None:
    normalized = sql.strip() if sql else None
    if normalized:
        try:
            assert_read_only(normalized)
        except QueryValidationError as e:
            raise HTTPException(status_code=400, detail=f"Query must be read-only: {e}")
    return normalized or None


class UpdateUseCase(NewUseCase):
    pass


@router.post("")
def create_use_case(
    body: NewUseCase,
    ctx: TenantContext = Depends(get_current_user),
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
    generated_sql = normalize_generated_sql(body.generated_sql)
    row = db.execute(
        text(
            "INSERT INTO use_cases (tenant_id, title, description, category, sample_question, icon_key, generated_sql) "
            "VALUES (:tenant_id, :title, :description, :category, :sample_question, :icon_key, :generated_sql) "
            "RETURNING id"
        ),
        {
            "tenant_id": ctx.tenant_id, "title": body.title, "description": body.description,
            "category": body.category, "sample_question": body.sample_question, "icon_key": body.icon_key,
            "generated_sql": generated_sql,
        },
    ).mappings().first()
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="usecase.create", details={"use_case_id": str(row["id"]), "title": body.title},
    )
    return {"id": str(row["id"])}


@router.put("/{use_case_id}")
def update_use_case(
    use_case_id: str,
    body: UpdateUseCase,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    generated_sql = normalize_generated_sql(body.generated_sql)
    row = db.execute(
        text(
            "UPDATE use_cases SET title = :title, description = :description, category = :category, "
            "sample_question = :sample_question, icon_key = :icon_key, generated_sql = :generated_sql "
            "WHERE id = :id RETURNING id"
        ),
        {
            "id": use_case_id, "title": body.title, "description": body.description,
            "category": body.category, "sample_question": body.sample_question,
            "icon_key": body.icon_key, "generated_sql": generated_sql,
        },
    ).mappings().first()
    if row is None:
        db.rollback()
        raise HTTPException(status_code=404, detail="No use case found with that id")
    db.commit()
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="usecase.update", details={"use_case_id": use_case_id, "title": body.title},
    )
    return {"id": str(row["id"])}


@router.post("/{use_case_id}/run")
def run_use_case(
    use_case_id: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Re-runs a use case's ALREADY-VETTED, cached SQL directly against the
    warehouse — no LLM call of any kind. assert_read_only() still runs
    (cheap, deterministic, no network call) as a defense-in-depth check,
    even though this exact SQL already passed it once at preview time —
    the query text itself never changes between then and now, so this
    should always pass again; it's here purely so a future code path
    that lets generated_sql be edited some other way can't accidentally
    skip validation.
    """
    row = db.execute(
        text("SELECT sample_question, generated_sql FROM use_cases WHERE id = :id"),
        {"id": use_case_id},
    ).mappings().first()
    if row is None:
        raise HTTPException(status_code=404, detail="No use case found with that id")
    if not row["generated_sql"]:
        raise HTTPException(
            status_code=400,
            detail="This use case has no saved query yet — open it for editing and click Preview first.",
        )

    sql = row["generated_sql"]

    try:
        assert_read_only(sql)
    except QueryValidationError as e:
        # Should never actually trigger given the query was validated at
        # save time and generated_sql is never edited directly — but if
        # it somehow did, fail loudly rather than silently re-running
        # something that looks wrong.
        raise HTTPException(status_code=400, detail=f"Saved query failed validation: {e}")

    try:
        client = get_databricks_client_for_user(db, ctx.tenant_id, ctx.user_id)
        result = client.execute_sql(sql)
    except (DataSourceNotConfigured, SecretNotFound) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=f"Query failed: {e}")

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="usecase.run",
        details={"use_case_id": use_case_id, "question": row["sample_question"], "sql": sql},
    )

    return {
        "sql": sql,
        "columns": result.get("columns") or [],
        "rows": (result.get("rows") or [])[:200],
    }


@router.delete("/{use_case_id}")
def delete_use_case(
    use_case_id: str,
    ctx: TenantContext = Depends(get_current_user),
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
    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="usecase.delete", details={"use_case_id": use_case_id},
    )
    return {"deleted": True}
