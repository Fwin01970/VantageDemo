"""
Schema Context (for Ask AI's direct-SQL path)
================================================
Ask AI no longer goes through Databricks Genie (see chat.py) — Genie
requires its own separate space/access grant, and a tenant without one
configured would have the data tool silently fail every time. Instead,
the LLM writes its own SQL directly against the SQL Warehouse, the same
way any other analytics app would.

This builds the "here's what you're allowed to work with" block for the
system prompt: table/column names and a business glossary. Deliberately
NOT actual records — no sample rows, no data values — only structure and
documentation. That boundary is what keeps this a genuine schema-
discovery step rather than a data leak: the LLM sees what things are
called and what they mean, never what's actually in them, until it runs
its own validated, read-only query.

WHERE THE GLOSSARY LIVES — IMPORTANT:
The business glossary is stored ENTIRELY in our own `schema_annotations`
table (our Postgres DB — see database/add_schema_annotations.sql), never
in the client's Databricks workspace. A client's data team owns their
Databricks schema, and reasonably may not want us running DDL against
it — even documentation-only DDL like `COMMENT ON TABLE`. So this module
never writes anything to Databricks. Table/column NAMES and TYPES are
still read live from Unity Catalog's information_schema (that's just
metadata discovery, same as listing tables — no different from what any
BI tool does), but the descriptive glossary text layered on top comes
entirely from our own database and is managed via the
/schema-annotations API (see routers/schema_annotations.py).

WHY THE GLOSSARY MATTERS (not just table/column names): a schema with
several similarly-named views — e.g. one computing loss ratio as paid-
claims/premium and another as incurred-losses/earned-premium — gives an
LLM genuine, reasonable grounds to second-guess itself and re-query
multiple tables "just to check", which wastes calls and can hit the
multi-step safety cap in chat_fallback.py without ever producing an
answer. A one-line note distinguishing them (or marking one as
canonical) resolves the ambiguity at the source, which is more durable
than telling the model "please don't do that" in the prompt alone —
though we keep that prompt instruction too, for tables no one has
annotated yet.

This deliberately only covers ONE catalog + schema per tenant (the pair
stored on their data_source_connections row) — a curated, single area
of the workspace, not "discover everything."

Cached in-process per tenant for a few minutes, since a schema doesn't
change often and re-fetching it on every single chat message would add
a slow round-trip to Databricks for no benefit. Adding/removing an
annotation via the API invalidates this cache immediately, so new notes
show up on the very next message rather than waiting out the TTL.
"""
import time
from sqlalchemy.orm import Session
from sqlalchemy import text as sql_text

from app.services.data_source_resolver import get_databricks_client_for_user, get_databricks_client_for_tenant
from app.services.databricks_client import DatabricksError

_CACHE_TTL_SECONDS = 600  # 10 minutes
_cache: dict[str, tuple[float, str]] = {}


class SchemaNotAvailable(Exception):
    """Raised when the tenant's connection has no catalog/schema
    configured, or the schema turned out to be empty — either way,
    there's nothing sensible to hand the LLM."""
    pass


def _get_local_annotations(
    db: Session, catalog: str, schema: str
) -> tuple[dict[str, str], dict[str, dict[str, str]]]:
    """
    Reads OUR OWN schema_annotations table — nothing here ever touches
    Databricks. Row-Level Security already scopes this to the calling
    tenant (same pattern as every other tenant-scoped table), so no
    explicit tenant_id filter is needed in the query itself.

    Returns (table_notes, column_notes):
      table_notes:  {table_name: note}
      column_notes: {table_name: {column_name: note}}
    """
    rows = db.execute(
        sql_text(
            """
            SELECT table_name, column_name, note
            FROM schema_annotations
            WHERE catalog_name = :catalog AND schema_name = :schema
            """
        ),
        {"catalog": catalog, "schema": schema},
    ).mappings().all()

    table_notes: dict[str, str] = {}
    column_notes: dict[str, dict[str, str]] = {}
    for r in rows:
        if r["column_name"] is None:
            table_notes[r["table_name"]] = r["note"]
        else:
            column_notes.setdefault(r["table_name"], {})[r["column_name"]] = r["note"]
    return table_notes, column_notes


def get_schema_context_for_tenant(
    db: Session, tenant_id: str, user_id: str | None = None, session_token: str | None = None
) -> str:
    """
    Returns a cached (or freshly built) plain-text description of the
    tenant's queryable tables/columns, including the business glossary
    from our own schema_annotations table. Raises DataSourceNotConfigured
    / SecretNotFound (from data_source_resolver) or SchemaNotAvailable if
    nothing usable could be built — callers should treat any of these as
    "the data tool isn't available right now" and fall back to a
    general-knowledge-only assistant, not surface a raw error.

    user_id is optional for backward compatibility, but should be passed
    whenever available — a user with their OWN personal Databricks
    credentials (see CREDENTIAL_MANAGEMENT_DESIGN.md) may be pointed at a
    different catalog/schema than their tenant's shared connection, so
    the cache key includes user_id to avoid serving one user's schema
    text to another.
    """
    cache_key = f"{tenant_id}:{user_id}" if user_id else tenant_id
    cached = _cache.get(cache_key)
    if cached and (time.time() - cached[0]) < _CACHE_TTL_SECONDS:
        return cached[1]

    client = (
        get_databricks_client_for_user(db, tenant_id, user_id, session_token)
        if user_id
        else get_databricks_client_for_tenant(db, tenant_id)
    )

    if not client.catalog or not client.schema:
        raise SchemaNotAvailable(
            "This tenant's Databricks connection has no catalog/schema configured."
        )

    # ── Structure — read-only from Databricks, required ────────────────
    cols_result = client.describe_columns(client.catalog, client.schema)
    col_names = cols_result["columns"]
    idx = {name: i for i, name in enumerate(col_names)}
    has_native_comment = "comment" in idx

    by_table_columns: dict[str, list[tuple[str, str, str]]] = {}  # table -> [(column, dtype, native_comment)]
    for row in cols_result["rows"]:
        table = row[idx["table_name"]]
        column = row[idx["column_name"]]
        dtype = row[idx["data_type"]]
        native_comment = (row[idx["comment"]] if has_native_comment else None) or ""
        by_table_columns.setdefault(table, []).append((column, dtype, native_comment))

    if not by_table_columns:
        raise SchemaNotAvailable(
            f"No tables found in {client.catalog}.{client.schema} — "
            f"check the catalog/schema configured for this tenant."
        )

    # ── OUR OWN glossary — the primary source of descriptive text ──────
    # This is entirely local (schema_annotations table); nothing here
    # reads from or writes to Databricks.
    local_table_notes, local_column_notes = _get_local_annotations(db, client.catalog, client.schema)

    # ── Native Databricks comments — optional bonus, READ-ONLY ─────────
    # If a client's data team happens to already have COMMENT ON TABLE/
    # COLUMN set (we never ask them to add these, never write them
    # ourselves), we still surface them — free extra context, at zero
    # write risk, since this is a plain SELECT against information_schema
    # exactly like the table/column listing above.
    native_table_comments: dict[str, str] = {}
    try:
        tables_result = client.describe_tables(client.catalog, client.schema)
        t_idx = {name: i for i, name in enumerate(tables_result["columns"])}
        for row in tables_result["rows"]:
            comment = row[t_idx["comment"]] if "comment" in t_idx else None
            if comment:
                native_table_comments[row[t_idx["table_name"]]] = comment
    except DatabricksError:
        pass  # optional enrichment — schema context still works without it

    # ── Relationships between tables — best-effort, may be empty ───────
    relationship_lines: list[str] = []
    try:
        rel_result = client.describe_relationships(client.catalog, client.schema)
        r_idx = {name: i for i, name in enumerate(rel_result["columns"])}
        for row in rel_result["rows"]:
            relationship_lines.append(
                f"- {row[r_idx['from_table']]}.{row[r_idx['from_column']]} -> "
                f"{row[r_idx['to_table']]}.{row[r_idx['to_column']]}"
            )
    except DatabricksError:
        pass

    # ── Assemble ─────────────────────────────────────────────────────
    lines = [
        f"You may query the following tables (catalog `{client.catalog}`, "
        f"schema `{client.schema}`). Always use the FULL three-part name "
        f"shown, e.g. `{client.catalog}.{client.schema}.<table_name>`. "
        f"Where a table or column has a description below, trust it over "
        f"guessing from the name alone — e.g. two tables can both look "
        f"like they compute the same metric while actually using "
        f"different definitions."
    ]
    for table in sorted(by_table_columns):
        fq_name = f"{client.catalog}.{client.schema}.{table}"
        # Our own note wins if present; otherwise fall back to whatever
        # Databricks-native comment happens to already exist.
        table_note = local_table_notes.get(table) or native_table_comments.get(table)
        header = f"- {fq_name}" + (f" — {table_note}" if table_note else "")
        lines.append(header)

        column_pieces = []
        for column, dtype, native_comment in by_table_columns[table]:
            note = local_column_notes.get(table, {}).get(column) or native_comment
            piece = f"{column} ({dtype})" + (f" — {note}" if note else "")
            column_pieces.append(piece)
        lines.append("    columns: " + ", ".join(column_pieces))

    if relationship_lines:
        lines.append("\nKnown relationships between tables:")
        lines.extend(relationship_lines)
    else:
        lines.append(
            "\n(No known relationships between these tables — if you need to join "
            "tables, infer the join key from matching column names/types.)"
        )

    context = "\n".join(lines)
    _cache[tenant_id] = (time.time(), context)
    return context


def invalidate_schema_cache(tenant_id: str) -> None:
    """Call this whenever a tenant's connection config changes, or an
    annotation is added/edited/removed, so stale schema text doesn't
    linger for up to _CACHE_TTL_SECONDS. Clears both the tenant-wide
    cache entry and any per-user entries for this tenant (cache keys are
    "tenant_id" or "tenant_id:user_id" — see get_schema_context_for_tenant)."""
    keys_to_remove = [k for k in _cache if k == tenant_id or k.startswith(f"{tenant_id}:")]
    for k in keys_to_remove:
        _cache.pop(k, None)
