"""
Schema Annotations — our own business glossary, NOT Databricks
==================================================================
This is the alternative to writing COMMENT ON TABLE/COLUMN directly in
a client's Databricks workspace. A client's data team owns their
Databricks schema, and reasonably may not want us running DDL against
it — even documentation-only DDL like COMMENT statements. So instead,
the glossary lives entirely in OUR OWN database (schema_annotations —
see database/add_schema_annotations.sql), tenant-scoped via the same
Row-Level Security pattern as everything else in this app.

Nothing in this file ever reads from or writes to Databricks. It's
plain CRUD against our own table. schema_context.py is what actually
merges these notes into what the LLM sees.

Gated by 'tenant:manage' — curating the glossary is an admin-of-your-
own-company action, same permission tier as managing tenant settings
generally.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext
from app.services.schema_context import invalidate_schema_cache

router = APIRouter(prefix="/schema-annotations", tags=["schema-annotations"])


class AnnotationIn(BaseModel):
    catalog_name: str
    schema_name: str
    table_name: str
    column_name: str | None = None  # None = this note describes the whole table
    note: str


class AnnotationOut(BaseModel):
    id: str
    catalog_name: str
    schema_name: str
    table_name: str
    column_name: str | None
    note: str


@router.get("", response_model=list[AnnotationOut])
def list_annotations(
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    """
    Lists this tenant's own glossary entries. Row-Level Security means
    this physically cannot return another tenant's annotations, even
    though the query itself doesn't filter by tenant_id — same guarantee
    used everywhere else in this app.
    """
    rows = db.execute(
        text(
            "SELECT id, catalog_name, schema_name, table_name, column_name, note "
            "FROM schema_annotations "
            "ORDER BY table_name, column_name NULLS FIRST"
        )
    ).mappings().all()
    return [
        AnnotationOut(
            id=str(r["id"]), catalog_name=r["catalog_name"], schema_name=r["schema_name"],
            table_name=r["table_name"], column_name=r["column_name"], note=r["note"],
        )
        for r in rows
    ]


@router.post("", response_model=AnnotationOut)
def create_annotation(
    body: AnnotationIn,
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    row = db.execute(
        text(
            """
            INSERT INTO schema_annotations
                (tenant_id, catalog_name, schema_name, table_name, column_name, note, created_by)
            VALUES (:tenant_id, :catalog, :schema, :table, :column, :note, :user_id)
            RETURNING id
            """
        ),
        {
            "tenant_id": ctx.tenant_id,
            "catalog": body.catalog_name,
            "schema": body.schema_name,
            "table": body.table_name,
            "column": body.column_name,
            "note": body.note,
            "user_id": ctx.user_id,
        },
    ).mappings().first()
    db.commit()

    # So the new note shows up on the very next Ask AI message instead
    # of waiting out the 10-minute schema cache.
    invalidate_schema_cache(ctx.tenant_id)

    return AnnotationOut(id=str(row["id"]), **body.model_dump())


@router.delete("/{annotation_id}")
def delete_annotation(
    annotation_id: str,
    ctx: TenantContext = Depends(require_permission("tenant:manage")),
    db: Session = Depends(get_db),
):
    result = db.execute(text("DELETE FROM schema_annotations WHERE id = :id"), {"id": annotation_id})
    db.commit()

    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Annotation not found")

    invalidate_schema_cache(ctx.tenant_id)
    return {"deleted": True}
