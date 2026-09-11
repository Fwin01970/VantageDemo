"""
Ask AI — conversational chat, with optional real-data tool access
=====================================================================
Conversations are now persisted server-side (chat_conversations /
chat_messages), not just held in frontend state. The frontend sends a
conversation_id and the new message only; the backend loads the real
history from the database rather than trusting whatever the client
claims the history was — same principle as everywhere else in this app:
the client proposes, the server resolves the truth.

Whether the assistant is even OFFERED the ability to query real company
data is decided fresh, per request, from:
  - does this user's role have 'data:query'?
  - does their tenant currently have an active Databricks connection?
Neither is hardcoded — a user/tenant without both simply gets a
general-knowledge assistant with no tool offered, no special-casing
required in this file.
"""
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel
import logging
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db
from app.auth.dependencies import get_current_user, bearer_scheme
from app.services.tenant_resolver import TenantContext
from app.services.data_source_resolver import get_databricks_client_for_user, get_llm_override_for_user, DataSourceNotConfigured, SecretNotFound
from app.services.schema_context import get_schema_context_for_tenant, SchemaNotAvailable
from app.services.audit import log_event
from app.services import conversations as convo
from app.services import governance_queue as hitl
from app.guardrails.engine import GuardrailEngine
from app.guardrails.llm_classifier import classify_question
from app.guardrails.query_validator import assert_read_only, QueryValidationError
from app.llm.chat_fallback import run_chat_turn, AllProvidersFailedError
from app.services.databricks_client import DatabricksError

router = APIRouter(prefix="/chat", tags=["chat"])
guardrails = GuardrailEngine()
logger = logging.getLogger(__name__)

# Ask AI talks DIRECTLY to the SQL Warehouse — it does NOT go through
# Databricks Genie. Genie lives on its own tab (routers/databricks.py)
# and requires its own separate space/access grant per tenant; routing
# Ask AI through it meant any tenant without a Genie space configured
# would have this tool fail on every single question. Instead, the LLM
# is given the tenant's real table/column names (see schema_context.py)
# and writes its own read-only SQL, which we validate and run ourselves.
DATA_TOOL = {
    "name": "query_company_data",
    "description": (
        "Run a single, read-only SQL SELECT query against the company's real Databricks "
        "data warehouse. Use this whenever answering accurately requires actual current "
        "numbers, records, or trends from the company's own systems — not for general "
        "knowledge questions, definitions, or predictions/opinions that don't need to be "
        "verified against real data. Use EXACTLY the fully-qualified table and column names "
        "given to you in your instructions — do not guess at names that weren't listed."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "sql": {
                "type": "string",
                "description": (
                    "A single valid, read-only SQL SELECT statement (Databricks SQL dialect), "
                    "using fully-qualified catalog.schema.table names exactly as given to you."
                ),
            }
        },
        "required": ["sql"],
    },
}


class ChatRequest(BaseModel):
    conversation_id: str | None = None  # None = start a new conversation
    message: str


class ChatResponse(BaseModel):
    conversation_id: str
    reply: str
    tool_used: bool
    tool_question: str | None = None
    provider_used: str | None = None
    tool_available: bool
    blocked: bool = False
    blocked_events: list[dict] | None = None
    # Raw columns/rows from the LAST successful query_company_data call
    # this turn (same data the LLM based its text answer on) — None
    # whenever no tool call happened, or the tool call errored/returned
    # nothing. Lets the frontend render a chart alongside the text reply
    # without re-querying or trying to parse numbers back out of prose.
    chart_data: dict | None = None
    # The following three fields exist so the Governance panel's SQL /
    # Guardrails / Grounding tabs — previously wired ONLY to Genie's
    # results — have something to show for Ask AI questions too. Genie
    # already computed all three; Ask AI computed the same input events
    # internally but only ever returned them on a BLOCKED request, never
    # ran the grounding check at all, and never returned the SQL it
    # executed. Structurally, the tabs were guaranteed to be empty for
    # any Ask AI session no matter how much real activity happened.
    sql: str | None = None
    guardrail_input_events: list[dict] = []
    grounding: dict | None = None


class ConversationSummary(BaseModel):
    id: str
    title: str
    updated_at: str


class MessageOut(BaseModel):
    role: str
    content: str
    chart_data: dict | None = None


def _system_prompt(ctx: TenantContext, tool_available: bool, schema_context: str = "") -> str:
    tool_note = (
        "You have a tool available to run real, read-only SQL against this company's live Databricks "
        "data warehouse — use it whenever the question needs actual current facts or figures, and answer "
        "directly from your own knowledge otherwise. Only write SELECT queries, and only use the exact "
        "table/column names listed below — never invent names that aren't listed.\n\n"
        "CRITICAL RULE — one query is enough, trust your own result:\n"
        "1. Pick the SINGLE table below whose name/description most directly matches the question.\n"
        "2. Write ONE query against it that already includes every breakdown the question asked for "
        "(e.g. if asked for 'all segments', GROUP BY the segment column in this same query — don't run "
        "a broad query and then a narrower one, and don't run a summary query and then peek at raw rows).\n"
        "3. The moment that query returns rows containing the metric and breakdown asked for, you are "
        "DONE — answer immediately using those numbers. Do not run a second query.\n\n"
        "Specifically NEVER do any of the following after you already have a usable result:\n"
        "- Never run `SELECT *` or 'let me look at a few raw rows' to double-check a calculation you "
        "already did correctly — the aggregate result IS the answer, inspecting raw rows adds nothing.\n"
        "- Never re-run the same metric against a DIFFERENT table to see if the numbers agree — tables "
        "with similar names can define a metric differently on purpose (e.g. paid-vs-premium vs "
        "incurred-vs-earned loss ratio); a second table returning a different number is not an error to "
        "resolve, it's simply a different metric you weren't asked for.\n"
        "The ONLY valid reasons to run a second query: your first query errored, returned zero rows, or "
        "you are missing one specific fact (like which year 'this year' refers to) needed before you can "
        "write the real query. Never run a second query just to feel more confident about a number you "
        "already have.\n\n"
        f"{schema_context}"
        if tool_available
        else "You do NOT have access to this company's live data right now — answer from general "
        "knowledge only, and clearly say so if the question really needs real company data you don't have."
    )
    return (
        f"You are a business analytics assistant for {ctx.tenant_name}, a company in the "
        f"{ctx.industry} industry. {tool_note} "
        "Always clearly distinguish three kinds of answers: (1) facts pulled from real company data, "
        "(2) predictions, forecasts, or projections — label these explicitly as such, e.g. 'AI "
        "projection, not verified against actual data', and (3) general knowledge or opinion not "
        "specific to this company. Never blur these categories together. Never fabricate specific "
        "numbers and present them as real company data. "
        "Formatting: use plain markdown only — headings, short paragraphs, bullet lists, and a real "
        "markdown table (| col | col |) when presenting a breakdown of rows. NEVER draw your own "
        "bar chart, ASCII/text chart, or any other text-art visualization (e.g. lines of brackets or "
        "block characters) — the application already renders a real, interactive chart from the "
        "underlying query result whenever one is applicable, so a hand-drawn text chart is redundant "
        "and often visually inconsistent with it. Just present the numbers; let the app chart them."
    )


@router.get("/conversations", response_model=list[ConversationSummary])
def list_my_conversations(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = convo.list_conversations(db, ctx.user_id)
    return [
        ConversationSummary(id=str(r["id"]), title=r["title"], updated_at=r["updated_at"].isoformat())
        for r in rows
    ]


@router.get("/conversations/{conversation_id}/messages", response_model=list[MessageOut])
def get_conversation_messages(
    conversation_id: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # RLS on chat_conversations/chat_messages means a conversation
    # belonging to another tenant simply won't be found here — this
    # returns empty rather than another tenant's data either way.
    return [
        MessageOut(role=m["role"], content=m["content"], chart_data=m.get("chart_data"))
        for m in convo.get_messages(db, conversation_id)
    ]


@router.delete("/conversations/{conversation_id}")
def delete_conversation(
    conversation_id: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Deletes a conversation and its messages (chat_messages cascades via
    its foreign key). This does NOT remove anything from audit_log — the
    audit trail is a separate table with no relationship to
    chat_conversations, so every question asked, blocked, or answered in
    this conversation remains fully visible in Governance → Audit Log
    even after the conversation itself is deleted from the sidebar.
    """
    title_row = db.execute(
        text("SELECT title FROM chat_conversations WHERE id = :id"), {"id": conversation_id}
    ).mappings().first()

    result = db.execute(text("DELETE FROM chat_conversations WHERE id = :id"), {"id": conversation_id})
    db.commit()

    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Conversation not found")

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="chat.conversation_deleted",
        details={"conversation_id": conversation_id, "title": title_row["title"] if title_row else None},
    )
    return {"deleted": True}


@router.post("/message", response_model=ChatResponse)
def send_message(
    body: ChatRequest,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    # IMPORTANT: we do NOT create the conversation row yet. A conversation
    # is only ever persisted once we know there's a real, guardrail-passed
    # message worth keeping — otherwise a blocked first message would
    # leave a permanent, empty, orphaned "New conversation" entry in the
    # sidebar with nothing inside it (a real bug we hit in practice).
    conversation_id = body.conversation_id
    is_first_message = body.conversation_id is None

    # Same guardrail checks as Genie — regex first, then LLM semantic pass.
    input_check = guardrails.evaluate_input(body.message)
    if input_check.blocked:
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="chat.message.blocked",
            details={"layer": "regex", "message": body.message,
                     "events": [{"policy": e.policy, "detail": e.detail} for e in input_check.events]},
        )
        return ChatResponse(
            conversation_id=conversation_id or "", reply="", tool_used=False, tool_available=False, blocked=True,
            blocked_events=[{"policy": e.policy, "detail": e.detail} for e in input_check.events],
        )

    llm_check = classify_question(input_check.processed_input, tenant_name=ctx.tenant_name, industry=ctx.industry)
    if llm_check.ran and (llm_check.jailbreak or llm_check.fairness_violation):
        policy = "LLM_JAILBREAK" if llm_check.jailbreak else "LLM_FAIRNESS"
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="chat.message.blocked",
            details={"layer": "llm", "message": body.message, "reason": llm_check.reason},
        )
        return ChatResponse(
            conversation_id=conversation_id or "", reply="", tool_used=False, tool_available=False, blocked=True,
            blocked_events=[{"policy": policy, "detail": llm_check.reason}],
        )

    # Off-topic is handled separately from jailbreak/fairness because it's
    # not a security violation — it's a scope boundary, and unlike the
    # other two, the model can be genuinely UNSURE rather than binary
    # right/wrong (e.g. "how do rates compare to last year" could be
    # about premiums or something else entirely depending on context).
    # High confidence -> block immediately, same as any other guardrail.
    # Low confidence -> don't answer AND don't hard-block either; this is
    # exactly the case the HITL queue exists for for — a human reviewer
    # sees it and decides, rather than the system guessing either way.
    if llm_check.ran and llm_check.off_topic:
        if llm_check.off_topic_confidence == "high":
            log_event(
                db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
                action="chat.message.blocked",
                details={"layer": "llm", "message": body.message, "reason": llm_check.reason, "check": "off_topic"},
            )
            return ChatResponse(
                conversation_id=conversation_id or "", reply="", tool_used=False, tool_available=False, blocked=True,
                blocked_events=[{
                    "policy": "OFF_TOPIC",
                    "detail": f"This assistant only answers questions about {ctx.tenant_name}'s business data and analytics. {llm_check.reason}".strip(),
                }],
            )
        else:
            review_id = hitl.create_review(
                db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
                question=body.message, check_type="off_topic", reason=llm_check.reason,
            )
            log_event(
                db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
                action="chat.message.hitl_flagged",
                details={"message": body.message, "reason": llm_check.reason, "review_id": review_id},
            )
            return ChatResponse(
                conversation_id=conversation_id or "", reply="", tool_used=False, tool_available=False, blocked=True,
                blocked_events=[{
                    "policy": "PENDING_REVIEW",
                    "detail": "This question was flagged for human review before an answer is given. "
                              "An analyst will follow up if it needs a response.",
                }],
            )

    if not llm_check.ran:
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="chat.llm_guardrail_unavailable", details={"error": llm_check.error},
        )

    # Guardrails passed — NOW it's worth actually creating/persisting.
    conversation_id = conversation_id or convo.create_conversation(db, ctx.tenant_id, ctx.user_id)

    # Persist the user's message, then load the REAL history from the
    # database (not whatever the client might claim it is).
    convo.append_message(db, conversation_id, "user", body.message)
    if is_first_message:
        convo.maybe_set_title(db, conversation_id, body.message)
    history = convo.get_messages(db, conversation_id)

    # Tool is only offered if the user's role has data:query AND we can
    # actually build a usable schema description for the LLM — a tenant
    # with a Databricks connection but no catalog/schema configured
    # (or Databricks unreachable right now) simply gets a
    # general-knowledge assistant instead of a tool that would fail on
    # every question. No Genie space is required for any of this.
    tool_available = False
    schema_context = ""
    if ctx.has_permission("data:query"):
        try:
            schema_context = get_schema_context_for_tenant(
                db, ctx.tenant_id, ctx.user_id, credentials.credentials
            )
            tool_available = True
        except (DataSourceNotConfigured, SecretNotFound, SchemaNotAvailable, DatabricksError):
            tool_available = False

    # Populated by tool_executor on every successful query this turn —
    # deliberately overwritten rather than appended, since only the LAST
    # successful query's rows are what the final text answer is actually
    # based on (see the "one query is enough" rule in the system prompt
    # above). Read back out after run_chat_turn() finishes.
    last_query_result: dict = {"columns": None, "rows": None, "sql": None}

    def tool_executor(tool_name: str, tool_input: dict) -> str:
        sql = (tool_input.get("sql") or "").strip()
        # Full multi-line SQL (with real table/column names and business
        # logic like the loss-ratio formula) only goes to DEBUG now —
        # previously this was INFO, meaning the complete query text was
        # written to stdout/whatever aggregates it on every single call,
        # which is more schema/logic exposure than a production log
        # stream should carry by default. INFO keeps a short one-line
        # preview so you can still see activity without the full text.
        logger.debug("Ask AI tool call — tenant=%s SQL: %s", ctx.tenant_id, sql)
        logger.info("Ask AI tool call — tenant=%s SQL preview: %s", ctx.tenant_id, " ".join(sql.split())[:80])

        try:
            assert_read_only(sql)
        except QueryValidationError as e:
            logger.warning("Ask AI SQL blocked by validator: %s", e)
            return f"Query blocked: {e}"

        try:
            client = get_databricks_client_for_user(
                db, ctx.tenant_id, ctx.user_id, credentials.credentials
            )
            result = client.execute_sql(sql)
        except (DataSourceNotConfigured, SecretNotFound, DatabricksError) as e:
            logger.warning("Ask AI query failed: %s", e)
            return f"Could not retrieve data: {e}"

        columns = result.get("columns") or []
        rows = (result.get("rows") or [])[:20]
        logger.info("Ask AI tool result — %d column(s), %d row(s) (showing up to 20)", len(columns), len(rows))

        # Only overwrite if this query actually returned something — a
        # preliminary lookup that errors or comes back empty (e.g. "what
        # years exist" hitting a typo'd table) shouldn't wipe out a GOOD
        # result from an earlier call in the same turn.
        if columns and rows:
            last_query_result["columns"] = columns
            last_query_result["rows"] = rows
            last_query_result["sql"] = sql

        # Small (1-2 column) results are almost always a preliminary lookup
        # (e.g. "what years exist") — no nudge needed, the model still has
        # a real query ahead of it. Anything wider than that already looks
        # like a substantive analytical result, which is exactly the case
        # where a model tends to want to double-check itself against a
        # different table or raw rows — so tell it plainly, right here in
        # the result it's about to react to, not just once at the top of
        # the conversation.
        if len(columns) >= 3 and rows:
            stop_note = (
                "\n\n[This result already includes real figures and a breakdown — if it answers the "
                "question, respond now with a final text answer using these numbers. Do not run another "
                "query against this or any other table to verify this result; a different table computing "
                "a similar-sounding metric differently is not a discrepancy to resolve.]"
            )
        else:
            stop_note = ""

        return f"Columns: {columns}\nRows (up to 20): {rows}{stop_note}"

    system_prompt = _system_prompt(ctx, tool_available, schema_context)
    provider_messages = [{"role": "system", "content": system_prompt}] + [
        {"role": m["role"], "content": m["content"]} for m in history
    ]

    # If this user has configured their own personal LLM API key (Profile
    # → Credentials), try it first — falls back to the tenant-wide chain
    # unchanged if they haven't (get_llm_override_for_user returns None).
    user_llm_override = get_llm_override_for_user(db, ctx.user_id)

    try:
        result = run_chat_turn(
            provider_messages, [DATA_TOOL] if tool_available else None, tool_executor,
            user_llm_override=user_llm_override,
        )
    except AllProvidersFailedError as e:
        # Full raw vendor error (request IDs, doc links, internal error
        # codes) stays in the server log and audit trail for whoever's
        # debugging this — but that's not what reaches the browser. The
        # user gets a short, classified sentence per provider instead
        # (quota/billing vs. rate limit vs. bad key vs. missing model),
        # since the raw JSON blob was neither actionable nor appropriate
        # to show an end user directly.
        logger.error("Ask AI — all LLM providers failed: %s", e)
        log_event(
            db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
            action="chat.llm_unavailable", details={"error": str(e)},
        )
        raise HTTPException(status_code=502, detail=e.user_facing_summary())

    logger.info(
        "Ask AI — provider=%s tool_used=%s reply_length=%d",
        result.provider_used, result.tool_used, len(result.text or ""),
    )
    if result.tool_used and not (result.text or "").strip():
        logger.warning(
            "Ask AI — tool ran successfully but the provider returned an EMPTY final reply "
            "(tenant=%s). This means the tool result never got summarized into text.",
            ctx.tenant_id,
        )

    # Only worth keeping/showing if there's more than one row of a single
    # value — a 1x1 result (e.g. "what's total premium this year?") is
    # already fully conveyed by the text answer, and charting a single
    # bar/point adds nothing but visual noise.
    chart_data = None
    if (
        result.tool_used
        and last_query_result["columns"]
        and last_query_result["rows"]
        and not (len(last_query_result["columns"]) == 1 and len(last_query_result["rows"]) == 1)
    ):
        chart_data = {"columns": last_query_result["columns"], "rows": last_query_result["rows"]}

    convo.append_message(db, conversation_id, "assistant", result.text, chart_data=chart_data)

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="chat.message",
        details={
            "message": body.message, "tool_used": result.tool_used,
            "tool_question": result.tool_question, "provider_used": result.provider_used,
        },
    )

    # Only worth sending to the frontend if there's more than one row of
    # a single value — a 1x1 result (e.g. "what's total premium this
    # year?") is already fully conveyed by the text answer, and charting
    # a single bar/point adds nothing but visual noise.
    # Grounding check — Genie has always run this; Ask AI never did,
    # which is the other half of why the Governance panel's Grounding
    # tab was always empty for Ask AI sessions. Only meaningful when the
    # tool actually ran and returned rows to check the summary against.
    grounding = None
    if result.tool_used and last_query_result["rows"]:
        g = guardrails.evaluate_output(result.text, last_query_result["rows"])
        grounding = {"score": g.grounding_score, "flagged": g.action == "FLAG"}

    return ChatResponse(
        conversation_id=conversation_id,
        reply=result.text,
        tool_used=result.tool_used,
        tool_question=result.tool_question,
        provider_used=result.provider_used,
        tool_available=tool_available,
        chart_data=chart_data,
        sql=last_query_result["sql"],
        guardrail_input_events=[{"policy": e.policy, "detail": e.detail} for e in input_check.events],
        grounding=grounding,
    )
