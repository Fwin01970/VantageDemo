-- ============================================================================
-- Ryze Infinity — Fix: RLS policies crash on empty-string tenant context
-- ============================================================================
-- ROOT CAUSE: our policies used
--     tenant_id = current_setting('app.current_tenant_id', true)::uuid
-- On a genuinely fresh connection this returns NULL (safe — the cast of
-- NULL is just NULL, and the row is correctly hidden). But after a RESET
-- of that setting (which can legitimately happen — e.g. connection
-- cleanup between pooled requests), Postgres returns an EMPTY STRING for
-- a custom setting, not NULL — and casting '' to uuid is a hard error,
-- crashing the whole query instead of safely denying access.
--
-- FIX: wrap it in NULLIF(..., '') so an empty string is treated exactly
-- like "not set" (NULL) before the cast ever happens — same safe "deny by
-- default" behavior in both cases, no crash either way.
--
-- This changes ONLY the policy expressions — no data is touched. Safe to
-- run on an existing database.
-- ============================================================================

CREATE OR REPLACE FUNCTION current_tenant_id_safe()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid;
$$;

DROP POLICY IF EXISTS tenant_isolation_tenants ON tenants;
CREATE POLICY tenant_isolation_tenants ON tenants
    USING (id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_users ON users;
CREATE POLICY tenant_isolation_users ON users
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_roles ON roles;
CREATE POLICY tenant_isolation_roles ON roles
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_dsc ON data_source_connections;
CREATE POLICY tenant_isolation_dsc ON data_source_connections
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_audit ON audit_log;
CREATE POLICY tenant_isolation_audit ON audit_log
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_use_cases ON use_cases;
CREATE POLICY tenant_isolation_use_cases ON use_cases
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_pinned_items ON pinned_items;
CREATE POLICY tenant_isolation_pinned_items ON pinned_items
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_conversations ON chat_conversations;
CREATE POLICY tenant_isolation_conversations ON chat_conversations
    USING (tenant_id = current_tenant_id_safe());

DROP POLICY IF EXISTS tenant_isolation_messages ON chat_messages;
CREATE POLICY tenant_isolation_messages ON chat_messages
    USING (conversation_id IN (SELECT id FROM chat_conversations));

GRANT EXECUTE ON FUNCTION current_tenant_id_safe() TO ryze_app;
