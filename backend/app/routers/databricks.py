"""
Phase 2 — Databricks connectivity endpoints, now with guardrails.

Each request's Databricks connection is resolved automatically from the
logged-in user's tenant (via data_source_resolver). On top of that, this
router now applies:

  - Query Validator (app/guardrails/query_validator.py) — blocks any
    write/administrative SQL on the one endpoint that accepts raw SQL
    from a caller (/data/query). Uses real SQL tokenization, not a
    regex that only checks the start of the string.
  - Guardrail Engine (app/guardrails/engine.py) — on /data/ask-genie,
    checks the question for jailbreak attempts, PII, and fairness
    violations BEFORE sending it to Genie, and checks Genie's summary
    for output grounding AFTER getting a response back.

NOT yet implemented (still to come, deliberately out of scope for this
pass): RBAC-based column/row/table permission filtering. Every logged-in
user with a configured Databricks connection currently has the same
level of access to their company's data — permission granularity is a
later phase.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.auth.dependencies import get_current_user
from app.services.rbac import require_permission
from app.services.tenant_resolver import TenantContext
from app.services.databricks_client import DatabricksClient, DatabricksError
from app.services.data_source_resolver import (
    get_databricks_client_for_user,
    DataSourceNotConfigured,
    SecretNotFound,
)
from app.guardrails.engine import GuardrailEngine
from app.guardrails.query_validator import assert_read_only, QueryValidationError
from app.guardrails.llm_classifier import classify_question
from app.services.audit import log_event

router = APIRouter(prefix="/data", tags=["databricks"])

# One shared instance is fine — the engine holds no per-request state,
# just compiled regex patterns.
guardrails = GuardrailEngine()


def get_client(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DatabricksClient:
    try:
        return get_databricks_client_for_user(db, ctx.tenant_id, ctx.user_id)
    except DataSourceNotConfigured as e:
        raise HTTPException(status_code=404, detail=str(e))
    except SecretNotFound as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/test-connection")
def test_connection(client: DatabricksClient = Depends(get_client)):
    """The simplest possible proof the connection works at all: runs
    `SELECT 1`. No guardrails needed — the query is hardcoded, not
    user-supplied."""
    try:
        result = client.execute_sql("SELECT 1 AS connection_test")
        return {"status": "connected", "result": result}
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.get("/discover/catalogs")
def discover_catalogs(client: DatabricksClient = Depends(get_client)):
    """Lists every catalog visible to this company's connection. Every
    discovery query is a fixed SHOW statement, not user-supplied SQL, so
    the query validator isn't needed here."""
    try:
        return client.list_catalogs()
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.get("/discover/schemas")
def discover_schemas(catalog: str, client: DatabricksClient = Depends(get_client)):
    try:
        return client.list_schemas(catalog)
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.get("/discover/tables")
def discover_tables(
    catalog: str,
    schema: str,
    client: DatabricksClient = Depends(get_client),
):
    try:
        return client.list_tables(catalog, schema)
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))


class RawQuery(BaseModel):
    sql: str


@router.post("/query")
def run_query(
    body: RawQuery,
    ctx: TenantContext = Depends(require_permission("data:query")),
    client: DatabricksClient = Depends(get_client),
    db: Session = Depends(get_db),
):
    """
    Runs caller-supplied SQL — this is the one endpoint where the Query
    Validator actually matters, since the SQL isn't fixed/hardcoded like
    the discovery endpoints above. Requires the 'data:query' permission
    (proves RBAC and query validation work together, even before
    column/row-level filtering exists). Both blocked and successful
    queries are written to the audit log.
    """
    try:
        assert_read_only(body.sql)
    except QueryValidationError as e:
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="data.query.blocked", details={"sql": body.sql, "reason": str(e)},
        )
        raise HTTPException(status_code=400, detail=str(e))

    try:
        result = client.execute_sql(body.sql)
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="data.query", details={"sql": body.sql, "row_count": len(result.get("rows", []))},
        )
        return result
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))


class GenieQuestion(BaseModel):
    question: str


@router.post("/ask-genie")
def ask_genie(
    body: GenieQuestion,
    ctx: TenantContext = Depends(require_permission("genie:access")),
    client: DatabricksClient = Depends(get_client),
    db: Session = Depends(get_db),
):
    """
    Sends a natural-language question to Genie, with guardrails applied
    before and after:

    BEFORE: the question is checked for jailbreak attempts, PII, and
    underwriting-fairness violations. A jailbreak/fairness match blocks
    the request entirely (400). A PII match doesn't block — it masks the
    PII out of the question before sending it to Genie.

    A SECOND, SMARTER PASS then runs an LLM classifier on anything the
    regex didn't already block — this catches paraphrased or indirectly
    worded jailbreak/fairness attempts that don't match a literal
    pattern (e.g. describing a discriminatory request abstractly instead
    of naming the protected characteristic directly). Tries Ollama
    (free/local) first, then Anthropic, then OpenAI. If every provider
    is unreachable, this check is skipped (fails open) rather than
    blocking a legitimate question because of our own infrastructure
    problem — that's recorded in the audit log either way.

    AFTER: Genie's natural-language summary is checked for "grounding" —
    do the numbers it mentions actually appear in the real returned rows,
    or did it invent them? A low grounding score doesn't block the
    response (the data itself is still real and useful) — it's flagged
    in the response instead, so the caller/UI can show a warning rather
    than silently trusting a possibly-fabricated summary.

    Every step here — blocked, flagged, or successful — is written to
    the audit log.
    """
    input_check = guardrails.evaluate_input(body.question)
    if input_check.blocked:
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="genie.question.blocked",
            details={
                "question": body.question,
                "layer": "regex",
                "events": [{"policy": e.policy, "detail": e.detail} for e in input_check.events],
            },
        )
        raise HTTPException(
            status_code=400,
            detail={
                "message": "This question was blocked by a safety guardrail.",
                "events": [{"policy": e.policy, "detail": e.detail} for e in input_check.events],
            },
        )

    # Second pass: LLM semantic classification, only on what the regex
    # already let through.
    llm_result = classify_question(input_check.processed_input)
    if llm_result.ran and (llm_result.jailbreak or llm_result.fairness_violation):
        policy = "LLM_JAILBREAK" if llm_result.jailbreak else "LLM_FAIRNESS"
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="genie.question.blocked",
            details={
                "question": body.question,
                "layer": "llm",
                "provider_used": llm_result.provider_used,
                "reason": llm_result.reason,
            },
        )
        raise HTTPException(
            status_code=400,
            detail={
                "message": "This question was blocked by a safety guardrail.",
                "events": [{"policy": policy, "detail": llm_result.reason}],
            },
        )
    if not llm_result.ran:
        # Fail open: infrastructure problem, not a content problem. Still
        # recorded so it's visible this pass was skipped, not silently missing.
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="genie.llm_guardrail_unavailable",
            details={"error": llm_result.error},
        )

    try:
        result = client.ask_genie(input_check.processed_input)
    except DatabricksError as e:
        raise HTTPException(status_code=502, detail=str(e))

    grounding_note = None
    if result.get("summary") and result.get("rows"):
        output_check = guardrails.evaluate_output(result["summary"], result["rows"])
        grounding_note = {
            "score": output_check.grounding_score,
            "flagged": output_check.action == "FLAG",
        }

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="genie.question",
        details={
            "question": input_check.processed_input,
            "row_count": result.get("row_count", 0),
            "grounding": grounding_note,
            "llm_guardrail_provider": llm_result.provider_used,
        },
    )

    return {
        **result,
        "guardrails": {
            "input_events": [{"policy": e.policy, "detail": e.detail} for e in input_check.events],
            "llm_check": {
                "ran": llm_result.ran,
                "provider_used": llm_result.provider_used,
            },
            "grounding": grounding_note,
        },
    }
