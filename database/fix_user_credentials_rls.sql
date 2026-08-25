-- ============================================================================
-- Fix: user_credentials RLS policy crashes on empty-string session vars
-- ============================================================================
-- Same root cause as fix_rls_empty_string.sql, just missed on this table
-- because it was added afterward: the policy cast
--     current_setting('app.current_tenant_id', true)::uuid
--     current_setting('app.current_user_id', true)::uuid
-- directly, without NULLIF(...,''). On a connection where that session
-- variable was RESET (not just never-set), Postgres returns '' rather
-- than NULL, and ''::uuid is a hard error — which is exactly the
-- `invalid input syntax for type uuid: ""` crash you hit on save.
--
-- Safe to run on an existing database — only replaces the policy
-- expression, touches no data.
-- ============================================================================

CREATE OR REPLACE FUNCTION current_user_id_safe()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
$$;

DROP POLICY IF EXISTS user_owns_credentials ON user_credentials;
CREATE POLICY user_owns_credentials ON user_credentials
    USING (
        tenant_id = current_tenant_id_safe()
        AND user_id = current_user_id_safe()
    );
