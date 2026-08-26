"""
Local Gold Client
===================
A stand-in for DatabricksClient with the exact same public interface
(execute_sql, describe_columns, describe_tables, describe_relationships)
— chat.py, schema_context.py, and genie's code never know or care which
one they're talking to. This one runs SQL directly against a schema in
our own Postgres (see database/add_banking_gold_demo.sql) instead of a
real Databricks SQL Warehouse.

Exists because we don't currently have real Databricks access for the
banking demo tenant — without this, Ask AI/Genie would have nothing to
query and would silently degrade to general-knowledge-only answers with
no real numbers. Swapping a tenant back to a genuine Databricks
connection later is a one-row UPDATE to data_source_connections
(platform back to 'databricks') — nothing here needs to change.
"""
from sqlalchemy import create_engine, text as sql_text

from app.config import DATABASE_URL
from app.services.databricks_client import DatabricksError, _assert_safe_identifier

# A single small connection pool, separate from the app's main
# RLS-scoped session — this schema isn't tenant-partitioned data (it's
# one shared demo dataset), so it deliberately does NOT go through
# set_tenant_context()/RLS the way real tenant tables do.
_engine = create_engine(DATABASE_URL, pool_size=3, pool_pre_ping=True)


class LocalGoldClient:
    def __init__(self, schema: str = "gold_demo"):
        _assert_safe_identifier(schema)
        self.schema = schema
        # Postgres has no catalog concept the way Unity Catalog does —
        # this exists purely so callers written against DatabricksClient
        # (schema_context.py's `client.catalog` / `client.schema` check,
        # `client.describe_columns(client.catalog, client.schema)`) work
        # unmodified against either client type. describe_columns()
        # below ignores whatever value is passed in as `catalog`.
        self.catalog = "local"

    def execute_sql(self, sql: str, timeout_seconds: int = 30) -> dict:
        """Mirrors DatabricksClient.execute_sql's return shape exactly:
        {columns: [...], rows: [[...], ...]}. The caller (chat.py's
        tool_executor) has already run assert_read_only() on `sql`
        before this is ever called — same trust boundary as the real
        Databricks path, not re-validated here."""
        try:
            with _engine.connect() as conn:
                result = conn.execute(sql_text(sql))
                columns = list(result.keys())
                rows = [list(row) for row in result.fetchall()]
                return {"columns": columns, "rows": rows}
        except Exception as e:
            raise DatabricksError(f"Local demo dataset query failed: {e}")

    def describe_columns(self, catalog: str, schema: str) -> dict:
        """catalog is ignored — Postgres has no catalog concept the way
        Unity Catalog does; `schema` is expected to be this client's own
        gold_demo schema, kept as a parameter only so callers written
        against DatabricksClient's signature don't need special-casing."""
        return self.execute_sql(
            f"SELECT table_name, column_name, data_type, NULL AS comment "
            f"FROM information_schema.columns "
            f"WHERE table_schema = '{self.schema}' "
            f"ORDER BY table_name, ordinal_position"
        )

    def describe_tables(self, catalog: str, schema: str) -> dict:
        # Postgres's information_schema.tables has no comment column —
        # real per-table documentation lives on pg_description, read via
        # obj_description(), which IS what COMMENT ON VIEW actually wrote
        # (see add_banking_gold_demo.sql's COMMENT ON VIEW statements).
        return self.execute_sql(
            f"SELECT c.relname AS table_name, obj_description(c.oid) AS comment "
            f"FROM pg_class c "
            f"JOIN pg_namespace n ON n.oid = c.relnamespace "
            f"WHERE n.nspname = '{self.schema}' AND c.relkind IN ('r', 'v')"
        )

    def describe_relationships(self, catalog: str, schema: str) -> dict:
        # No FK relationships declared in the demo schema — matches
        # DatabricksClient's own graceful empty-result fallback rather
        # than raising, since this is a nice-to-have, not required.
        return {"columns": ["from_table", "from_column", "to_table", "to_column"], "rows": []}
