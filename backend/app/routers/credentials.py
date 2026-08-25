"""
Per-User Credentials API
==========================
See CREDENTIAL_MANAGEMENT_DESIGN.md for the full design. Key rule
enforced everywhere in this file: a raw secret NEVER appears in a
response body, a log line, or an error message — only masked strings
(mask_secret) or opaque secret_ref values, which are safe to return/log
since they reveal nothing about the underlying secret.
"""
import logging
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import get_db, set_tenant_context
from app.services.tenant_resolver import TenantContext
from app.auth.dependencies import get_current_user, bearer_scheme
from app.services.audit import log_event
from app.services.secret_store import get_secret_store, mask_secret, SecretStoreError
from app.services.credential_session_cache import (
    set_session_credentials, get_session_credentials, clear_session_credentials,
)
from app.services.databricks_client import DatabricksClient, DatabricksError
from app.llm.providers import GeminiProvider, AnthropicProvider, OpenAIProvider, LLMError
from app import config

router = APIRouter(prefix="/credentials", tags=["credentials"])
logger = logging.getLogger(__name__)

LLM_PROVIDERS = {"openai", "anthropic", "gemini"}  # 'azure_openai' intentionally not wired
# yet — same OpenAI-compatible API shape, but Azure OpenAI's URL includes
# a deployment name and api-version we don't have a real endpoint to test
# against here; the credentials FORM can still collect it (stored as
# llm_provider='azure_openai'), but validate() below will say so plainly
# rather than pretending to test something we can't.


class CredentialsIn(BaseModel):
    databricks_host: str | None = None
    databricks_warehouse_id: str | None = None
    databricks_genie_space_id: str | None = None
    databricks_catalog: str | None = None
    databricks_schema: str | None = None
    databricks_pat: str | None = None  # raw — never stored as-is, never echoed back
    llm_provider: str | None = None
    llm_api_key: str | None = None  # raw — same rule

    @field_validator(
        "databricks_host", "databricks_warehouse_id", "databricks_genie_space_id",
        "databricks_catalog", "databricks_schema", "databricks_pat",
        "llm_provider", "llm_api_key",
        mode="before",
    )
    @classmethod
    def _strip_whitespace(cls, v):
        # A stray leading/trailing space or newline from copy-pasting a
        # key/token is invisible in the UI but makes the value a DIFFERENT
        # string as far as the provider's API is concerned — this produced
        # a genuinely confusing 401 from Gemini (PAT auth happened to
        # tolerate it, Google's key validation didn't) that had nothing to
        # do with the actual key being wrong. Stripping once here, at the
        # API boundary, means every downstream use (session cache, secret
        # store, schema_context, chat tool calls) only ever sees the
        # cleaned value.
        return v.strip() if isinstance(v, str) else v


class ValidateResult(BaseModel):
    databricks: dict | None = None
    llm: dict | None = None


class SaveRequest(CredentialsIn):
    persist: bool = False


class CredentialsStatus(BaseModel):
    configured: bool
    persisted: bool
    databricks_host: str | None = None
    databricks_warehouse_id: str | None = None
    databricks_genie_space_id: str | None = None
    databricks_catalog: str | None = None
    databricks_schema: str | None = None
    databricks_pat_masked: str | None = None
    llm_provider: str | None = None
    llm_api_key_masked: str | None = None
    last_validated_at: str | None = None
    last_validation_ok: bool | None = None


def _test_databricks(host: str, pat: str, warehouse_id: str) -> dict:
    if not (host and pat and warehouse_id):
        return {"ok": False, "detail": "Host, warehouse ID, and PAT are all required to test Databricks."}
    try:
        client = DatabricksClient(host=host, token=pat, warehouse_id=warehouse_id)
        client.execute_sql("SELECT 1 AS connection_test")
        return {"ok": True, "detail": "Connected successfully."}
    except DatabricksError as e:
        # str(e) here comes from our own DatabricksError messages, which
        # already never include the token (see databricks_client.py) —
        # safe to return directly.
        return {"ok": False, "detail": str(e)}


def _test_llm(provider_name: str, api_key: str) -> dict:
    if not (provider_name and api_key):
        return {"ok": False, "detail": "Provider and API key are both required to test the LLM connection."}
    if provider_name not in LLM_PROVIDERS:
        return {"ok": False, "detail": f"'{provider_name}' isn't a supported provider yet."}
    try:
        # Use whatever model the rest of the app is actually configured to
        # use (app/config.py) rather than a separately hardcoded literal
        # here — a hardcoded model name here would silently drift out of
        # sync the next time a provider deprecates a model version, which
        # is exactly what happened with the first version of this check
        # (hardcoded "gemini-2.0-flash", deprecated in favor of
        # gemini-3.6-flash — this test failed even though the user's real
        # API key and the app's own chat path were both working fine).
        if provider_name == "gemini":
            provider = GeminiProvider(api_key, config.GEMINI_MODEL)
        elif provider_name == "anthropic":
            provider = AnthropicProvider(api_key, config.ANTHROPIC_MODEL)
        else:
            provider = OpenAIProvider(api_key, config.OPENAI_MODEL)
        provider.generate("Reply with the single word: ok", timeout_seconds=15)
        return {"ok": True, "detail": "Connected successfully."}
    except LLMError as e:
        return {"ok": False, "detail": str(e)}


@router.post("/validate", response_model=ValidateResult)
def validate_credentials(
    body: CredentialsIn,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Tests connectivity WITHOUT persisting anything, anywhere — not the
    database, not the secret store, not even the session cache. Purely
    a "does this work" check before the user is offered the save prompt.
    """
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    result = ValidateResult()
    if body.databricks_host or body.databricks_pat:
        result.databricks = _test_databricks(
            body.databricks_host or "", body.databricks_pat or "", body.databricks_warehouse_id or ""
        )
    if body.llm_provider or body.llm_api_key:
        result.llm = _test_llm(body.llm_provider or "", body.llm_api_key or "")

    log_event(
        db, tenant_id=ctx.tenant_id, user_id=ctx.user_id,
        action="credentials.validate",
        details={
            "databricks_ok": result.databricks["ok"] if result.databricks else None,
            "llm_ok": result.llm["ok"] if result.llm else None,
        },
    )
    return result


@router.get("/status", response_model=CredentialsStatus)
def get_status(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    row = db.execute(
        text(
            "SELECT databricks_host, databricks_warehouse_id, databricks_genie_space_id, "
            "databricks_catalog, databricks_schema, databricks_pat_secret_ref, "
            "llm_provider, llm_api_key_secret_ref, last_validated_at, last_validation_ok "
            "FROM user_credentials WHERE user_id = :uid"
        ),
        {"uid": ctx.user_id},
    ).mappings().first()

    if row:
        store = get_secret_store(db)
        pat_masked = None
        key_masked = None
        try:
            if row["databricks_pat_secret_ref"]:
                pat_masked = mask_secret(store.retrieve(row["databricks_pat_secret_ref"]))
            if row["llm_api_key_secret_ref"]:
                key_masked = mask_secret(store.retrieve(row["llm_api_key_secret_ref"]))
        except SecretStoreError as e:
            logger.warning("Could not decrypt stored secret for masking (user=%s): %s", ctx.user_id, e)

        return CredentialsStatus(
            configured=True, persisted=True,
            databricks_host=row["databricks_host"],
            databricks_warehouse_id=row["databricks_warehouse_id"],
            databricks_genie_space_id=row["databricks_genie_space_id"],
            databricks_catalog=row["databricks_catalog"],
            databricks_schema=row["databricks_schema"],
            databricks_pat_masked=pat_masked,
            llm_provider=row["llm_provider"],
            llm_api_key_masked=key_masked,
            last_validated_at=row["last_validated_at"].isoformat() if row["last_validated_at"] else None,
            last_validation_ok=row["last_validation_ok"],
        )

    session_creds = get_session_credentials(creds.credentials)
    if session_creds:
        return CredentialsStatus(
            configured=True, persisted=False,
            databricks_host=session_creds.get("databricks_host"),
            databricks_warehouse_id=session_creds.get("databricks_warehouse_id"),
            databricks_genie_space_id=session_creds.get("databricks_genie_space_id"),
            databricks_catalog=session_creds.get("databricks_catalog"),
            databricks_schema=session_creds.get("databricks_schema"),
            databricks_pat_masked=mask_secret(session_creds["databricks_pat"]) if session_creds.get("databricks_pat") else None,
            llm_provider=session_creds.get("llm_provider"),
            llm_api_key_masked=mask_secret(session_creds["llm_api_key"]) if session_creds.get("llm_api_key") else None,
        )

    return CredentialsStatus(configured=False, persisted=False)


@router.post("/", response_model=CredentialsStatus)
def save_credentials(
    body: SaveRequest,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    if not body.persist:
        # Session-only path — nothing touches the database at all.
        set_session_credentials(creds.credentials, body.model_dump())
        log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.save_session_only", details={})
        return get_status(ctx, db, creds)

    # Persisted path
    store = get_secret_store(db)
    pat_ref = store.store("databricks-pat", body.databricks_pat) if body.databricks_pat else None
    key_ref = store.store("llm-api-key", body.llm_api_key) if body.llm_api_key else None

    db.execute(
        text(
            """
            INSERT INTO user_credentials
                (tenant_id, user_id, databricks_host, databricks_warehouse_id,
                 databricks_genie_space_id, databricks_catalog, databricks_schema,
                 databricks_pat_secret_ref, llm_provider, llm_api_key_secret_ref, updated_at)
            VALUES
                (:tenant_id, :user_id, :host, :warehouse_id, :genie_space_id, :catalog, :schema_name,
                 :pat_ref, :llm_provider, :key_ref, now())
            ON CONFLICT (user_id) DO UPDATE SET
                databricks_host = EXCLUDED.databricks_host,
                databricks_warehouse_id = EXCLUDED.databricks_warehouse_id,
                databricks_genie_space_id = EXCLUDED.databricks_genie_space_id,
                databricks_catalog = EXCLUDED.databricks_catalog,
                databricks_schema = EXCLUDED.databricks_schema,
                databricks_pat_secret_ref = EXCLUDED.databricks_pat_secret_ref,
                llm_provider = EXCLUDED.llm_provider,
                llm_api_key_secret_ref = EXCLUDED.llm_api_key_secret_ref,
                updated_at = now()
            """
        ),
        {
            "tenant_id": ctx.tenant_id, "user_id": ctx.user_id,
            "host": body.databricks_host, "warehouse_id": body.databricks_warehouse_id,
            "genie_space_id": body.databricks_genie_space_id, "catalog": body.databricks_catalog,
            "schema_name": body.databricks_schema, "pat_ref": pat_ref,
            "llm_provider": body.llm_provider, "key_ref": key_ref,
        },
    )
    db.commit()

    # Never log the values — only that a save happened.
    log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.save_persisted", details={})

    return get_status(ctx, db, creds)


@router.post("/test", response_model=ValidateResult)
def test_existing_credentials(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    """Re-validates whatever is currently stored/session-cached, WITHOUT
    requiring the user to re-enter secrets — the backend already has them."""
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    row = db.execute(
        text(
            "SELECT databricks_host, databricks_warehouse_id, databricks_pat_secret_ref, "
            "llm_provider, llm_api_key_secret_ref FROM user_credentials WHERE user_id = :uid"
        ),
        {"uid": ctx.user_id},
    ).mappings().first()

    if row:
        store = get_secret_store(db)
        pat = store.retrieve(row["databricks_pat_secret_ref"]) if row["databricks_pat_secret_ref"] else None
        key = store.retrieve(row["llm_api_key_secret_ref"]) if row["llm_api_key_secret_ref"] else None
        host, warehouse_id, llm_provider = row["databricks_host"], row["databricks_warehouse_id"], row["llm_provider"]
    else:
        session_creds = get_session_credentials(creds.credentials)
        if not session_creds:
            raise HTTPException(status_code=404, detail="No credentials configured to test.")
        pat = session_creds.get("databricks_pat")
        key = session_creds.get("llm_api_key")
        host, warehouse_id, llm_provider = (
            session_creds.get("databricks_host"), session_creds.get("databricks_warehouse_id"),
            session_creds.get("llm_provider"),
        )

    result = ValidateResult(
        databricks=_test_databricks(host or "", pat or "", warehouse_id or "") if (host or pat) else None,
        llm=_test_llm(llm_provider or "", key or "") if (llm_provider or key) else None,
    )

    if row:
        db.execute(
            text(
                "UPDATE user_credentials SET last_validated_at = now(), last_validation_ok = :ok WHERE user_id = :uid"
            ),
            {
                "ok": bool((not result.databricks or result.databricks["ok"]) and (not result.llm or result.llm["ok"])),
                "uid": ctx.user_id,
            },
        )
        db.commit()

    log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.test", details={})
    return result


@router.put("/rotate-pat", response_model=CredentialsStatus)
def rotate_pat(
    new_pat: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    row = db.execute(
        text("SELECT databricks_pat_secret_ref FROM user_credentials WHERE user_id = :uid"),
        {"uid": ctx.user_id},
    ).mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="No persisted credentials to rotate — save credentials first.")

    store = get_secret_store(db)
    new_ref = store.rotate("databricks-pat", row["databricks_pat_secret_ref"], new_pat.strip())

    db.execute(
        text("UPDATE user_credentials SET databricks_pat_secret_ref = :ref, updated_at = now() WHERE user_id = :uid"),
        {"ref": new_ref, "uid": ctx.user_id},
    )
    db.commit()
    log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.rotate_pat", details={})
    return get_status(ctx, db, creds)


@router.put("/rotate-llm-key", response_model=CredentialsStatus)
def rotate_llm_key(
    new_key: str,
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    row = db.execute(
        text("SELECT llm_api_key_secret_ref FROM user_credentials WHERE user_id = :uid"),
        {"uid": ctx.user_id},
    ).mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="No persisted credentials to rotate — save credentials first.")

    store = get_secret_store(db)
    new_ref = store.rotate("llm-api-key", row["llm_api_key_secret_ref"], new_key.strip())

    db.execute(
        text("UPDATE user_credentials SET llm_api_key_secret_ref = :ref, updated_at = now() WHERE user_id = :uid"),
        {"ref": new_ref, "uid": ctx.user_id},
    )
    db.commit()
    log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.rotate_llm_key", details={})
    return get_status(ctx, db, creds)


@router.delete("/")
def delete_credentials(
    ctx: TenantContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    creds: HTTPAuthorizationCredentials = Depends(bearer_scheme),
):
    set_tenant_context(db, ctx.tenant_id, ctx.user_id)
    row = db.execute(
        text(
            "SELECT databricks_pat_secret_ref, llm_api_key_secret_ref FROM user_credentials WHERE user_id = :uid"
        ),
        {"uid": ctx.user_id},
    ).mappings().first()

    if row:
        store = get_secret_store(db)
        for ref in (row["databricks_pat_secret_ref"], row["llm_api_key_secret_ref"]):
            if ref:
                try:
                    store.delete(ref)
                except SecretStoreError as e:
                    logger.warning("Failed to delete secret during credential removal (ref=%s): %s", ref, e)
        db.execute(text("DELETE FROM user_credentials WHERE user_id = :uid"), {"uid": ctx.user_id})
        db.commit()

    clear_session_credentials(creds.credentials)
    log_event(db, tenant_id=ctx.tenant_id, user_id=ctx.user_id, action="credentials.delete", details={})
    return {"deleted": True}
