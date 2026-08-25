-- ── Per-user credentials ────────────────────────────────────────────────
-- See CREDENTIAL_MANAGEMENT_DESIGN.md for the full design. Two tables:
--   user_credentials — metadata only (host, warehouse id, etc.) plus an
--                      opaque secret_ref — NEVER a raw secret.
--   local_secrets     — the actual encrypted bytes, for the local/dev
--                      SecretStore implementation. Kept in a SEPARATE
--                      table from user_credentials on purpose: a full
--                      dump of user_credentials alone reveals nothing
--                      but opaque reference strings.
--
-- When Azure Key Vault is wired in for a real deployment, local_secrets
-- simply isn't used — secret_ref values point into the vault instead,
-- and this table stays empty. Nothing else changes.

CREATE TABLE user_credentials (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id                     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    databricks_host             TEXT,
    databricks_warehouse_id     TEXT,
    databricks_genie_space_id   TEXT,
    databricks_catalog          TEXT,
    databricks_schema           TEXT,
    databricks_pat_secret_ref   TEXT,   -- opaque handle into the secret store — NEVER the PAT itself

    llm_provider                TEXT,   -- 'openai' | 'azure_openai' | 'anthropic' | 'gemini'
    llm_api_key_secret_ref      TEXT,   -- opaque handle — NEVER the key itself

    last_validated_at           TIMESTAMPTZ,
    last_validation_ok          BOOLEAN,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id)
);

CREATE INDEX idx_user_credentials_user ON user_credentials (user_id);

ALTER TABLE user_credentials ENABLE ROW LEVEL SECURITY;

-- Deliberately stricter than every other RLS policy in this app: checks
-- user_id, not just tenant_id. Credentials are personal, not
-- company-shared, so a user must only ever see their OWN row.
--
-- Uses current_tenant_id_safe() (from fix_rls_empty_string.sql) and
-- current_user_id_safe() (defined here) rather than casting
-- current_setting(...) directly — a RESET session variable returns ''
-- (not NULL) in Postgres, and ''::uuid is a hard crash, not a safe
-- "no rows match." NULLIF(...,'') inside each function treats '' the
-- same as "not set," which is what actually makes this deny-by-default
-- instead of error-by-default.
CREATE OR REPLACE FUNCTION current_user_id_safe()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
$$;

CREATE POLICY user_owns_credentials ON user_credentials
    USING (
        tenant_id = current_tenant_id_safe()
        AND user_id = current_user_id_safe()
    );


-- ── Local encrypted secret store (default; Azure Key Vault is the
--    documented alternative — see secret_store.py) ─────────────────────
CREATE TABLE local_secrets (
    secret_ref   TEXT PRIMARY KEY,     -- e.g. "local:3f9a2b1c-..."
    ciphertext   TEXT NOT NULL,        -- Fernet-encrypted, base64
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- No RLS here deliberately — this table is never queried by a raw
-- tenant/user-scoped request; only secret_store.py touches it, using
-- the exact opaque ref it was handed, and it runs with the app's own
-- service-level DB role, not a per-request tenant context. Access
-- control lives at the user_credentials row level (above) — you can
-- only ever obtain a secret_ref for a secret you're allowed to read.
