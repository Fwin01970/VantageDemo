-- ============================================================================
-- RYZE INFINITY — TENANT DATABASE TEMPLATE
-- ============================================================================
-- Run this ONCE for every new company, against a brand new, separate
-- database you create just for them (e.g. "tenant_vantage_insurance").
-- Then add ONE row to the Platform database's `tenants` table pointing
-- at it (db_name = the database name you used here).
--
-- Notice there is NO "tenant_id" column anywhere in this file. That's
-- on purpose — this whole database belongs to exactly one company, so
-- there's nothing to filter by. This is what makes every table simpler
-- than before: no extra column to remember, no risk of ever forgetting
-- a WHERE tenant_id = ... check, because there's nothing to check
-- against — the separate database itself IS the wall between companies.
--
-- Only a FEW tables get privacy rules (Row-Level Security), and only
-- for things that need to stay private to ONE PERSON even within the
-- same company (their saved credentials, their own chat history, their
-- personal Genie settings, their dashboard). Everything else in a
-- company's data — its use cases, its business glossary, its shared
-- Databricks connection, its audit log — is visible to everyone in that
-- company who has the right permission, the same simple way a shared
-- office filing cabinet works.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Reads Postgres session variable app.current_user_id, safely — an
-- empty string (which happens when the variable was never set) would
-- normally crash a UUID comparison; NULLIF turns that into a clean
-- NULL instead, so a policy check just correctly matches nothing rather
-- than erroring.
CREATE OR REPLACE FUNCTION current_user_id_safe() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::UUID;
$$ LANGUAGE sql STABLE;


-- ============================================================================
-- People, roles, permissions
-- ============================================================================

CREATE TABLE users (
    id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email                  TEXT NOT NULL UNIQUE,
    display_name           TEXT NOT NULL,
    password_hash          TEXT,
    auth_provider          TEXT NOT NULL DEFAULT 'local',   -- 'local' | 'google' | 'microsoft' | 'github'
    oauth_subject          TEXT,
    is_active              BOOLEAN NOT NULL DEFAULT true,
    failed_login_attempts  INT NOT NULL DEFAULT 0,
    locked_until           TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at          TIMESTAMPTZ
);

CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL UNIQUE,        -- e.g. 'Team Member'
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Same fixed list of permission codes in every tenant database — copy
-- this exact INSERT into every new tenant so the meaning of each code
-- never drifts between companies.
CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL
);

INSERT INTO permissions (code, description) VALUES
    ('data:query',        'Ask natural-language questions against this company''s data (Ask AI tab)'),
    ('genie:access',      'Use the Genie tab'),
    ('tenant:manage',     'Create/edit Use Cases and business glossary notes'),
    ('audit:view',        'View this company''s own Governance panel (activity feed, HITL queue)'),
    ('governance:manage', 'Approve/reject/hold borderline (HITL) questions');

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- Every new tenant starts with one simple role, held identically by
-- everyone — no separate "admin vs viewer" tier inside a company
-- anymore (only the Platform Super Admin manages users/tenants).
INSERT INTO roles (id, name, description) VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'Team Member', 'Full access for this company — every user has the same permissions');
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-0000000000a1', id FROM permissions;


-- ============================================================================
-- Business content — visible tenant-wide (to anyone with the right
-- permission), simple, no per-row privacy rules needed
-- ============================================================================

CREATE TABLE use_cases (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title             TEXT NOT NULL,
    description       TEXT,
    category          TEXT,
    sample_question   TEXT NOT NULL,
    icon_key          TEXT,
    generated_sql     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE schema_annotations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name  TEXT NOT NULL,
    column_name TEXT,
    note        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE governance_reviews (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id        UUID REFERENCES users(id) ON DELETE SET NULL,
    question       TEXT NOT NULL,
    check_type     TEXT NOT NULL,
    reason         TEXT,
    status         TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | rejected | hold
    reviewed_by    UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at    TIMESTAMPTZ,
    decision_note  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,
    details     JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- This company's shared Databricks (or other) connection — "Query
-- Parameters," managed by the Platform Super Admin for this one tenant.
CREATE TABLE data_source_connections (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform    TEXT NOT NULL,             -- 'databricks' | 'local_demo'
    config      JSONB NOT NULL DEFAULT '{}'::jsonb,   -- host, warehouse_id, catalog, schema
    secret_ref  TEXT,                       -- POINTER to the real secret, never the secret itself
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================================
-- Genie settings — tenant-wide default, OR one person's personal
-- override (user_id NULL = default for everyone; a real user_id = just
-- for them). Not secret, just personal preference, so this is visible
-- tenant-wide too — no RLS needed, simple to read.
-- ============================================================================

CREATE TABLE genie_query_parameter_fields (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id       UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL = default for everyone
    field_name    TEXT NOT NULL,
    options       TEXT[] NOT NULL,
    display_order INT NOT NULL DEFAULT 0
);

CREATE TABLE genie_question_templates (
    id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id   UUID REFERENCES users(id) ON DELETE CASCADE,     -- NULL = default for everyone
    template  TEXT NOT NULL
);
CREATE UNIQUE INDEX genie_question_templates_scope_idx
    ON genie_question_templates (COALESCE(user_id, '00000000-0000-0000-0000-000000000000'));

CREATE TABLE genie_suggested_questions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id       UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL = default for everyone
    question_text TEXT NOT NULL,
    display_order INT NOT NULL DEFAULT 0
);


-- ============================================================================
-- PRIVATE tables — only these get Row-Level Security, because these are
-- the only things that need to stay private to ONE person within a
-- company that otherwise shares everything openly.
-- ============================================================================

-- Each person's own personal Databricks/LLM credentials.
CREATE TABLE user_credentials (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                     UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    databricks_host             TEXT,
    databricks_warehouse_id     TEXT,
    databricks_catalog          TEXT,
    databricks_schema           TEXT,
    databricks_pat_secret_ref   TEXT,
    databricks_genie_space_id   TEXT,
    llm_provider                TEXT,
    llm_api_key_secret_ref      TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE user_credentials ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_owns_credentials ON user_credentials
    USING (user_id = current_user_id_safe());

-- The actual encrypted secret values user_credentials' *_secret_ref
-- columns point at.
CREATE TABLE local_secrets (
    secret_ref      TEXT PRIMARY KEY,
    encrypted_value TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Each person's own Ask AI conversation history.
CREATE TABLE chat_conversations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE chat_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_owns_conversations ON chat_conversations
    USING (user_id = current_user_id_safe());

CREATE TABLE chat_messages (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id  UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    role             TEXT NOT NULL,       -- 'user' | 'assistant'
    content          TEXT NOT NULL,
    chart_data       JSONB,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_owns_messages ON chat_messages
    USING (conversation_id IN (SELECT id FROM chat_conversations WHERE user_id = current_user_id_safe()));

-- Who has shared their whole dashboard with whom — by email, only
-- between two people who both already have a login in this same
-- company (the lookup for this happens in the tenant's own users
-- table, so it can never reach across into another company at all).
-- Defined BEFORE pinned_items since pinned_items' own sharing policy
-- (below) needs to reference this table.
CREATE TABLE dashboard_shares (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shared_with_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (owner_user_id, shared_with_user_id)
);
ALTER TABLE dashboard_shares ENABLE ROW LEVEL SECURITY;
CREATE POLICY dashboard_shares_owner_full ON dashboard_shares
    FOR ALL USING (owner_user_id = current_user_id_safe());
CREATE POLICY dashboard_shares_recipient_read ON dashboard_shares
    FOR SELECT USING (shared_with_user_id = current_user_id_safe());

-- Dashboard pins — private to whoever pinned them, unless that person
-- has shared their WHOLE dashboard with you (dashboard_shares, above).
CREATE TABLE pinned_items (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source      TEXT NOT NULL,          -- 'ask_ai' | 'genie' | 'use_case'
    item_type   TEXT NOT NULL,          -- 'insight' | 'table' | 'chart'
    title       TEXT NOT NULL,
    payload     JSONB NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE pinned_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY pinned_items_owner_full ON pinned_items
    FOR ALL USING (user_id = current_user_id_safe());
CREATE POLICY pinned_items_shared_read ON pinned_items
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM dashboard_shares ds
        WHERE ds.owner_user_id = pinned_items.user_id
          AND ds.shared_with_user_id = current_user_id_safe()
    ));
