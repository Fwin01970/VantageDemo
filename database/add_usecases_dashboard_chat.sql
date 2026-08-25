-- ============================================================================
-- Ryze Infinity — Use Cases, Dashboard Pinning, Chat Conversation History
-- ============================================================================
-- Three new, tenant-scoped, RLS-protected tables. Nothing here is
-- industry-specific in structure — the seed data below happens to be
-- insurance/banking flavored because those are our two demo tenants, but
-- a new tenant in a different industry would get its own rows via the
-- same table, no code changes required.
--
-- Run this AFTER seed.sql (and after create_app_role.sql, since it also
-- grants access to ryze_app at the bottom).
-- ============================================================================

CREATE TABLE use_cases (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    description     TEXT NOT NULL,
    category        TEXT NOT NULL,
    sample_question TEXT NOT NULL,
    icon_key        TEXT NOT NULL DEFAULT 'trending-up',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE pinned_items (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source      TEXT NOT NULL,          -- 'ask_ai' | 'genie'
    item_type   TEXT NOT NULL,          -- 'insight' | 'table' | 'chart'
    title       TEXT NOT NULL,
    payload     JSONB NOT NULL,         -- shape depends on item_type
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_conversations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL DEFAULT 'New conversation',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chat_messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL,      -- 'user' | 'assistant'
    content         TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Row-Level Security — same pattern as every other tenant-scoped table ──
ALTER TABLE use_cases          ENABLE ROW LEVEL SECURITY;
ALTER TABLE pinned_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages      ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_use_cases ON use_cases
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_pinned_items ON pinned_items
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_conversations ON chat_conversations
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- chat_messages has no tenant_id column of its own — it's scoped through
-- its parent conversation, which is itself already tenant-isolated above.
CREATE POLICY tenant_isolation_messages ON chat_messages
    USING (conversation_id IN (SELECT id FROM chat_conversations));

GRANT SELECT, INSERT, UPDATE, DELETE ON use_cases, pinned_items, chat_conversations, chat_messages TO ryze_app;

-- ============================================================================
-- Seed data — demo use cases per tenant (illustrates dynamic, per-industry
-- content; a real onboarding flow would let a Tenant Admin manage these
-- via a UI rather than SQL, which is a reasonable future enhancement)
-- ============================================================================

INSERT INTO use_cases (tenant_id, title, description, category, sample_question, icon_key) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Loss ratio trend', 'Compare loss ratio across regions and product lines.', 'Claims', 'Show me the loss ratio trend by region for this year', 'trending-up'),
    ('11111111-1111-1111-1111-111111111111', 'Anomaly detection', 'Find unusual claims before they become material issues.', 'Claims', 'Are there any unusual claims this month?', 'scan-search'),
    ('11111111-1111-1111-1111-111111111111', 'Settlement performance', 'Monitor settlement time and paid vs reserved amounts.', 'Finance', 'What is our average settlement time this quarter?', 'badge-dollar-sign'),
    ('22222222-2222-2222-2222-222222222222', 'Loan portfolio risk', 'Review delinquency rates and exposure by loan type.', 'Risk', 'Show delinquency rates by loan type this quarter', 'trending-up'),
    ('22222222-2222-2222-2222-222222222222', 'Transaction anomalies', 'Find unusual transaction patterns before they escalate.', 'Risk', 'Are there any unusual transactions this week?', 'scan-search');
