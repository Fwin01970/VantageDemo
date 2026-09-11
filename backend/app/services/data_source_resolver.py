"""
Data Source Resolver
======================
Given a tenant, finds out which data platform they're connected to and
builds a ready-to-use client for it — automatically, based on who's
logged in. No one has to pick a company or a workspace; it's resolved
from the database, the same way the tenant/role/permissions already are.

The actual secret (the Databricks token) is NEVER stored in plaintext in
the database. Persisted credentials use an opaque `secret_ref` resolved
by the configured secret store; session-only credentials stay in process
memory for the authenticated session.
"""
import os
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.services.databricks_client import DatabricksClient
from app.services.local_gold_client import LocalGoldClient
from app.services.credential_session_cache import get_session_credentials


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
        raise DataSourceNotConfigured(
            "No shared Databricks credential is configured. Add your Databricks "
            "credentials in the Credentials tab."
        )

    token = os.getenv(secret_ref)
    if not token:
        raise DataSourceNotConfigured(
            "No shared Databricks credential is configured. Add your Databricks "
            "credentials in the Credentials tab, then choose whether to save "
            "them permanently or use them for this session only."
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


def get_databricks_client_for_user(
    db: Session, tenant_id: str, user_id: str, session_token: str | None = None
) -> "DatabricksClient | LocalGoldClient":
    """
    NEW — see CREDENTIAL_MANAGEMENT_DESIGN.md. Checks whether THIS
    SPECIFIC USER has configured their own personal Databricks
    credentials (via Profile → Credentials); if so, uses those. If not,
    falls back to get_databricks_client_for_tenant() exactly as before —
    so a tenant where no one has set up personal credentials behaves
    identically to before this feature existed. Nothing breaks for
    anyone who never touches the new settings page.
    """
    if session_token:
        session_creds = get_session_credentials(session_token)
        if session_creds and session_creds.get("databricks_host") and session_creds.get("databricks_pat"):
            return DatabricksClient(
                host=session_creds["databricks_host"],
                token=session_creds["databricks_pat"],
                warehouse_id=session_creds.get("databricks_warehouse_id", ""),
                genie_space_id=session_creds.get("databricks_genie_space_id"),
                catalog=session_creds.get("databricks_catalog"),
                schema=session_creds.get("databricks_schema"),
            )

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
