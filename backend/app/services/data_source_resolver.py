"""
Data Source Resolver
======================
Given a tenant, finds out which data platform they're connected to and
builds a ready-to-use client for it — automatically, based on who's
logged in. No one has to pick a company or a workspace; it's resolved
from the database, the same way the tenant/role/permissions already are.

The actual secret (the Databricks token) is NEVER stored in the
database — only a `secret_ref`, a pointer to where the real value lives
(right now, an environment variable name; later, a proper secrets
manager). This function is the one place that turns a pointer into a
usable client.
"""
import os
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.services.databricks_client import DatabricksClient
from app.services.local_gold_client import LocalGoldClient


class DataSourceNotConfigured(Exception):
    """Raised when the current tenant has no active connection for the
    requested platform — e.g. logging in as a company that hasn't been
    set up with Databricks yet."""
    pass


class SecretNotFound(Exception):
    """Raised when a connection points at a secret (secret_ref) that
    isn't actually set anywhere the app can find it."""
    pass


def get_databricks_client_for_tenant(db: Session, tenant_id: str) -> "DatabricksClient | LocalGoldClient":
    """
    Looks up the CALLING TENANT'S OWN data connection (Row-Level Security
    on data_source_connections means this query physically cannot see
    another tenant's row, even though it doesn't filter by tenant_id
    itself — same pattern as /admin/tenants).

    Returns either a real DatabricksClient or a LocalGoldClient depending
    on the tenant's `platform` — everything downstream (chat.py, Genie,
    schema_context.py) calls the same methods on either one and neither
    knows or cares which it got. Swapping a tenant from the local demo
    dataset to a real Databricks workspace later is exactly one UPDATE
    to this row's `platform` column.
    """
    row = db.execute(
        text(
            """
            SELECT platform, config, secret_ref
            FROM data_source_connections
            WHERE platform IN ('databricks', 'local_demo') AND is_active = true
            LIMIT 1
            """
        )
    ).mappings().first()

    if row is None:
        raise DataSourceNotConfigured(
            "Your company doesn't have a data connection set up yet."
        )

    config = row["config"]

    if row["platform"] == "local_demo":
        return LocalGoldClient(schema=config.get("schema", "gold_demo"))

    secret_ref = row["secret_ref"]

    if not secret_ref:
        raise SecretNotFound("This connection has no secret_ref configured.")

    token = os.getenv(secret_ref)
    if not token:
        raise SecretNotFound(
            f"Expected a secret in the environment variable '{secret_ref}', "
            f"but it isn't set. Check backend/.env."
        )

    missing = [k for k in ("host", "warehouse_id") if not config.get(k)]
    if missing:
        raise DataSourceNotConfigured(
            f"Your company's Databricks connection is missing: {', '.join(missing)}"
        )

    return DatabricksClient(
        host=config["host"],
        token=token,
        warehouse_id=config["warehouse_id"],
        genie_space_id=config.get("genie_space_id"),
        catalog=config.get("catalog"),
        schema=config.get("schema"),
    )


def get_databricks_client_for_user(db: Session, tenant_id: str, user_id: str) -> "DatabricksClient | LocalGoldClient":
    """
    NEW — see CREDENTIAL_MANAGEMENT_DESIGN.md. Checks whether THIS
    SPECIFIC USER has configured their own personal Databricks
    credentials (via Profile → Credentials); if so, uses those. If not,
    falls back to get_databricks_client_for_tenant() exactly as before —
    so a tenant where no one has set up personal credentials behaves
    identically to before this feature existed. Nothing breaks for
    anyone who never touches the new settings page.
    """
    row = db.execute(
        text(
            """
            SELECT databricks_host, databricks_warehouse_id, databricks_genie_space_id,
                   databricks_catalog, databricks_schema, databricks_pat_secret_ref
            FROM user_credentials
            WHERE user_id = :user_id
            """
        ),
        {"user_id": user_id},
    ).mappings().first()

    has_personal_databricks = bool(
        row and row["databricks_host"] and row["databricks_warehouse_id"] and row["databricks_pat_secret_ref"]
    )
    if not has_personal_databricks:
        return get_databricks_client_for_tenant(db, tenant_id)

    from app.services.secret_store import get_secret_store, SecretStoreError

    try:
        store = get_secret_store(db)
        token = store.retrieve(row["databricks_pat_secret_ref"])
    except SecretStoreError as e:
        raise SecretNotFound(f"Could not retrieve your personal Databricks credential: {e}")

    return DatabricksClient(
        host=row["databricks_host"],
        token=token,
        warehouse_id=row["databricks_warehouse_id"],
        genie_space_id=row["databricks_genie_space_id"],
        catalog=row["databricks_catalog"],
        schema=row["databricks_schema"],
    )


def get_llm_override_for_user(db: Session, user_id: str) -> tuple[str, str] | None:
    """
    NEW — returns (provider_name, api_key) if this user has configured
    their own personal LLM API key, else None. Callers should prepend a
    provider built from this to the front of the normal fallback chain,
    and fall through to the tenant-wide chain unchanged if this is None
    — same backward-compatibility guarantee as the Databricks resolver
    above.
    """
    row = db.execute(
        text("SELECT llm_provider, llm_api_key_secret_ref FROM user_credentials WHERE user_id = :user_id"),
        {"user_id": user_id},
    ).mappings().first()

    if not row or not row["llm_provider"] or not row["llm_api_key_secret_ref"]:
        return None

    from app.services.secret_store import get_secret_store, SecretStoreError

    try:
        store = get_secret_store(db)
        api_key = store.retrieve(row["llm_api_key_secret_ref"])
    except SecretStoreError:
        return None  # fall back to the tenant-wide chain rather than failing the whole request

    return row["llm_provider"], api_key
