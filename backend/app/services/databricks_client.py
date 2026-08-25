"""
Databricks Client (Phase 2)
============================
This talks to two Databricks REST APIs:

1. The SQL Statement Execution API — runs a SQL query against a SQL
   Warehouse and returns rows. Used both for real queries and for
   "discovery" (listing catalogs/schemas/tables) since both are just SQL.

2. The Genie Conversations API — lets you ask a plain-English question
   and get back the SQL Genie generated, plus the results.

WHY REST CALLS INSTEAD OF THE OFFICIAL databricks-sdk:
Our architecture record says to prefer the official SDK over hand-rolled
HTTP calls, and that's still the right long-term goal. For this first
connectivity test, though, we're deliberately using directly-documented
REST endpoints — the same ones already proven to work in the reference
codebase's genie.js/query.js — rather than the SDK's higher-level
wrapper methods, whose exact shape we can't verify without hitting a
real workspace first. Once this is confirmed working end-to-end, it's a
reasonable follow-up to swap this for the official SDK.

This module knows nothing about tenants, RBAC, or the rest of the app —
it only knows how to talk to ONE Databricks workspace, using whatever
connection details it's given.
"""
import time
import httpx


class DatabricksError(Exception):
    """Raised whenever Databricks returns something we can't proceed with."""
    pass


class DatabricksClient:
    def __init__(
        self,
        host: str,
        token: str,
        warehouse_id: str,
        genie_space_id: str | None = None,
        catalog: str | None = None,
        schema: str | None = None,
    ):
        # 'host' should be just the hostname, e.g.
        # "dbc-xxxxxxx-xxxx.cloud.databricks.com" — no "https://" prefix
        # and no trailing slash. We normalize it defensively here so a
        # copy-pasted full URL doesn't break everything downstream.
        self.host = host.replace("https://", "").replace("http://", "").rstrip("/")
        self.token = token
        self.warehouse_id = warehouse_id
        self.genie_space_id = genie_space_id
        # catalog/schema scope the Ask AI (non-Genie) schema discovery
        # below to one curated area of the workspace, same way
        # genie_space_id scopes the Genie tab. Optional — a tenant with
        # neither configured simply won't get the Ask AI data tool.
        self.catalog = catalog
        self.schema = schema
        self._base_url = f"https://{self.host}"
        self._headers = {"Authorization": f"Bearer {self.token}"}

    # ── Low-level SQL execution ──────────────────────────────────────
    def execute_sql(self, sql: str, timeout_seconds: int = 30) -> dict:
        """
        Runs a SQL statement against the configured warehouse and returns
        {columns: [...], rows: [[...], ...]}.

        This is intentionally the ONE place all SQL goes through, whether
        it came from a discovery query, a direct test query, or Genie.
        """
        try:
            with httpx.Client(timeout=timeout_seconds) as client:
                submit = client.post(
                    f"{self._base_url}/api/2.0/sql/statements",
                    headers=self._headers,
                    json={
                        "warehouse_id": self.warehouse_id,
                        "statement": sql,
                        "wait_timeout": "10s",  # Databricks will hold the request open briefly
                    },
                )
                if submit.status_code not in (200, 201):
                    raise DatabricksError(
                        f"Failed to submit query (HTTP {submit.status_code}): {submit.text[:500]}"
                    )

                body = submit.json()
                statement_id = body["statement_id"]
                state = body.get("status", {}).get("state")

                # If it didn't finish within the initial wait, poll until it does.
                deadline = time.time() + timeout_seconds
                while state in ("PENDING", "RUNNING") and time.time() < deadline:
                    time.sleep(1)
                    poll = client.get(
                        f"{self._base_url}/api/2.0/sql/statements/{statement_id}",
                        headers=self._headers,
                    )
                    body = poll.json()
                    state = body.get("status", {}).get("state")

                if state != "SUCCEEDED":
                    error_msg = body.get("status", {}).get("error", {}).get("message", "unknown error")
                    raise DatabricksError(f"Query did not succeed (state={state}): {error_msg}")

                columns = [c["name"] for c in body["manifest"]["schema"]["columns"]]
                rows = body.get("result", {}).get("data_array", [])
                return {"columns": columns, "rows": rows}
        except DatabricksError:
            raise
        except httpx.ConnectError as e:
            raise DatabricksError(
                f"Could not reach Databricks host '{self.host}' — check DATABRICKS_HOST "
                f"is correct and your network/VPN can reach it. ({e})"
            )
        except httpx.TimeoutException as e:
            raise DatabricksError(f"Databricks request timed out: {e}")
        except httpx.HTTPError as e:
            raise DatabricksError(f"Unexpected error talking to Databricks: {e}")

    # ── Discovery helpers (so we don't need pre-existing knowledge of
    #    what's in the workspace — everything below is just SQL) ─────
    def list_catalogs(self) -> dict:
        return self.execute_sql("SHOW CATALOGS")

    def list_schemas(self, catalog: str) -> dict:
        # Basic guard against accidental injection via the catalog name —
        # this endpoint isn't RBAC-protected yet (that's a later phase),
        # so keep it defensive even for this internal test tool.
        _assert_safe_identifier(catalog)
        return self.execute_sql(f"SHOW SCHEMAS IN {catalog}")

    def list_tables(self, catalog: str, schema: str) -> dict:
        _assert_safe_identifier(catalog)
        _assert_safe_identifier(schema)
        return self.execute_sql(f"SHOW TABLES IN {catalog}.{schema}")

    def describe_columns(self, catalog: str, schema: str) -> dict:
        """
        One query that returns every table + column + data type + column
        COMMENT in the given schema, via Unity Catalog's
        information_schema. The comment is whatever the data team wrote
        via `COMMENT ON COLUMN ...` in Databricks — this is the "business
        glossary" layer: e.g. a column literally named `LossRatioPct`
        might have a comment clarifying it's paid-basis, not incurred-
        basis, which is exactly the ambiguity that causes an LLM to
        second-guess itself across similarly-named tables.
        """
        _assert_safe_identifier(catalog)
        _assert_safe_identifier(schema)
        return self.execute_sql(
            f"SELECT table_name, column_name, data_type, comment "
            f"FROM {catalog}.information_schema.columns "
            f"WHERE table_schema = '{schema}' "
            f"ORDER BY table_name, ordinal_position"
        )

    def describe_tables(self, catalog: str, schema: str) -> dict:
        """
        Table-level COMMENTs (e.g. `COMMENT ON TABLE ... IS '...'`), if
        the data team has documented them — this is what lets us tell the
        LLM "this is the canonical loss-ratio table, use this one" at the
        table level, not just per-column.
        """
        _assert_safe_identifier(catalog)
        _assert_safe_identifier(schema)
        return self.execute_sql(
            f"SELECT table_name, comment "
            f"FROM {catalog}.information_schema.tables "
            f"WHERE table_schema = '{schema}'"
        )

    def describe_relationships(self, catalog: str, schema: str) -> dict:
        """
        Best-effort: informational foreign-key relationships between
        tables in this schema, if the data team has declared any via
        `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY`. Unity Catalog
        does NOT enforce these — they're purely documentation — but
        plenty of teams still declare them for exactly this kind of
        tooling. Returns an empty result (never raises) if none exist or
        this workspace's Unity Catalog version doesn't expose these
        particular information_schema views, since this is a nice-to-have
        on top of the columns/tables info above, not a hard requirement.
        """
        _assert_safe_identifier(catalog)
        _assert_safe_identifier(schema)
        try:
            return self.execute_sql(
                f"""
                SELECT
                    kcu1.table_name AS from_table, kcu1.column_name AS from_column,
                    kcu2.table_name AS to_table, kcu2.column_name AS to_column
                FROM {catalog}.information_schema.referential_constraints rc
                JOIN {catalog}.information_schema.key_column_usage kcu1
                  ON rc.constraint_name = kcu1.constraint_name
                 AND rc.constraint_schema = kcu1.table_schema
                JOIN {catalog}.information_schema.key_column_usage kcu2
                  ON rc.unique_constraint_name = kcu2.constraint_name
                 AND rc.unique_constraint_schema = kcu2.table_schema
                WHERE rc.constraint_schema = '{schema}'
                """
            )
        except DatabricksError:
            return {"columns": ["from_table", "from_column", "to_table", "to_column"], "rows": []}

    # ── Genie (natural-language-to-SQL) ──────────────────────────────
    def ask_genie(self, question: str, space_id: str | None = None, max_polls: int = 60) -> dict:
        """
        Sends a plain-English question to Genie, waits for it to generate
        and run SQL, and returns the SQL it wrote plus the resulting rows.
        """
        space = space_id or self.genie_space_id
        if not space:
            raise DatabricksError("No Genie space configured")

        try:
            with httpx.Client(timeout=30) as client:
                start = client.post(
                    f"{self._base_url}/api/2.0/genie/spaces/{space}/start-conversation",
                    headers=self._headers,
                    json={"content": question},
                )
                if start.status_code != 200:
                    raise DatabricksError(
                        f"Genie start-conversation failed (HTTP {start.status_code}): {start.text[:500]}"
                    )
                start_body = start.json()
                conversation_id = start_body["conversation_id"]
                message_id = start_body["message_id"]

                terminal_states = {"COMPLETED", "FAILED", "CANCELED"}
                message_body = None
                for attempt in range(max_polls):
                    poll = client.get(
                        f"{self._base_url}/api/2.0/genie/spaces/{space}/conversations/"
                        f"{conversation_id}/messages/{message_id}",
                        headers=self._headers,
                    )
                    message_body = poll.json()
                    state = message_body.get("status")
                    if state in terminal_states:
                        break
                    time.sleep(1 if attempt < 5 else 2)
                else:
                    raise DatabricksError("Genie timed out waiting for a response")

                if message_body.get("status") != "COMPLETED":
                    raise DatabricksError(f"Genie did not complete: status={message_body.get('status')}")

                attachments = message_body.get("attachments", [])
                query_attachment = next((a for a in attachments if a.get("query", {}).get("statement_id")), None)
                summary_attachment = next((a for a in attachments if a.get("text")), None)

                sql = query_attachment.get("query", {}).get("query") if query_attachment else None
                summary = summary_attachment.get("text", {}).get("content") if summary_attachment else None
                statement_id = query_attachment.get("query", {}).get("statement_id") if query_attachment else None

                columns, rows = [], []
                if statement_id:
                    # Small pause — mirrors the reference implementation, which
                    # found immediate reads sometimes hit a transient 429.
                    time.sleep(1.5)
                    result = client.get(
                        f"{self._base_url}/api/2.0/sql/statements/{statement_id}",
                        headers=self._headers,
                    )
                    result_body = result.json()
                    columns = [c["name"] for c in result_body.get("manifest", {}).get("schema", {}).get("columns", [])]
                    rows = result_body.get("result", {}).get("data_array", [])

                return {
                    "sql": sql,
                    "summary": summary,
                    "columns": columns,
                    "rows": rows,
                    "row_count": len(rows),
                    "conversation_id": conversation_id,
                    "message_id": message_id,
                }
        except DatabricksError:
            raise
        except httpx.ConnectError as e:
            raise DatabricksError(
                f"Could not reach Databricks host '{self.host}' — check DATABRICKS_HOST "
                f"is correct and your network/VPN can reach it. ({e})"
            )
        except httpx.TimeoutException as e:
            raise DatabricksError(f"Databricks request timed out: {e}")
        except httpx.HTTPError as e:
            raise DatabricksError(f"Unexpected error talking to Databricks: {e}")


def _assert_safe_identifier(name: str) -> None:
    """Very basic guard: catalog/schema names should just be plain
    identifiers, never arbitrary SQL. This is not a substitute for the
    real query validator planned for later — just a sanity check for
    this early discovery tool."""
    if not name.replace("_", "").replace("-", "").isalnum():
        raise DatabricksError(f"Rejected unsafe identifier: {name!r}")
