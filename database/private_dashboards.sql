-- ============================================================================
-- Private dashboards: pins are private by default, visible to others
-- only once explicitly shared
-- ============================================================================
-- Previously, pinned_items lived in each tenant's private schema with NO
-- row-level restriction at all beyond tenant isolation — confirmed live
-- during testing that any user in a tenant could see every other user's
-- pins. That was flagged as a real problem: a pin should be private to
-- whoever created it until they deliberately choose to share it.
--
-- Adds:
--   - is_shared BOOLEAN column (default false — private by default)
--   - TWO separate RLS policies, not one:
--       - a SELECT-only policy that also allows shared rows through
--       - an ALL policy scoped to the owner only
--     Two permissive policies for the same command are OR'd together in
--     Postgres, so the net effect is: SELECT returns (your own rows) OR
--     (anyone's shared rows), while INSERT/UPDATE/DELETE only ever work
--     on your OWN rows — a non-owner can see a shared pin but can never
--     edit, unshare, or delete someone else's pin just because they can
--     see it.
--
-- Run this after drop_superseded_public_tables.sql (order relative to
-- later files doesn't matter — this only touches pinned_items).
-- ============================================================================

ALTER TABLE tenant_template.pinned_items ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false;

-- Extend provisioning (full function body again, same as every other
-- CREATE OR REPLACE in this project's migration history — nothing from
-- the original provisioning is dropped, just added to).
CREATE OR REPLACE FUNCTION public.provision_tenant_application_schema(p_tenant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM public.tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL OR v_schema !~ '^tenant_[0-9a-f]{32}$' THEN
        RAISE EXCEPTION 'Invalid tenant schema for %', p_tenant_id;
    END IF;

    EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.use_cases (LIKE tenant_template.use_cases INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.pinned_items (LIKE tenant_template.pinned_items INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.chat_conversations (LIKE tenant_template.chat_conversations INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.chat_messages (LIKE tenant_template.chat_messages INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.governance_reviews (LIKE tenant_template.governance_reviews INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.schema_annotations (LIKE tenant_template.schema_annotations INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.user_credentials (LIKE tenant_template.user_credentials INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.local_secrets (LIKE tenant_template.local_secrets INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_query_parameter_fields (LIKE tenant_template.genie_query_parameter_fields INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_question_templates (LIKE tenant_template.genie_question_templates INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_suggested_questions (LIKE tenant_template.genie_suggested_questions INCLUDING ALL)', v_schema);
    EXECUTE format(
        'CREATE UNIQUE INDEX IF NOT EXISTS genie_question_templates_scope_idx ON %I.genie_question_templates (tenant_id, COALESCE(user_id, ''00000000-0000-0000-0000-000000000000''))',
        v_schema
    );
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.data_source_connections (LIKE tenant_template.data_source_connections INCLUDING ALL)', v_schema);

    EXECUTE format('ALTER TABLE %I.user_credentials ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS user_owns_credentials ON %I.user_credentials', v_schema);
    EXECUTE format('CREATE POLICY user_owns_credentials ON %I.user_credentials USING (tenant_id = public.current_tenant_id_safe() AND user_id = public.current_user_id_safe())', v_schema);

    EXECUTE format('ALTER TABLE %I.genie_query_parameter_fields ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS genie_fields_visible ON %I.genie_query_parameter_fields', v_schema);
    EXECUTE format(
        'CREATE POLICY genie_fields_visible ON %I.genie_query_parameter_fields USING '
        '(tenant_id = public.current_tenant_id_safe() AND (user_id = public.current_user_id_safe() OR user_id IS NULL))',
        v_schema
    );

    EXECUTE format('ALTER TABLE %I.genie_question_templates ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS genie_template_visible ON %I.genie_question_templates', v_schema);
    EXECUTE format(
        'CREATE POLICY genie_template_visible ON %I.genie_question_templates USING '
        '(tenant_id = public.current_tenant_id_safe() AND (user_id = public.current_user_id_safe() OR user_id IS NULL))',
        v_schema
    );

    EXECUTE format('ALTER TABLE %I.genie_suggested_questions ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS genie_suggestions_visible ON %I.genie_suggested_questions', v_schema);
    EXECUTE format(
        'CREATE POLICY genie_suggestions_visible ON %I.genie_suggested_questions USING '
        '(tenant_id = public.current_tenant_id_safe() AND (user_id = public.current_user_id_safe() OR user_id IS NULL))',
        v_schema
    );

    EXECUTE format('ALTER TABLE %I.data_source_connections ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS query_parameters_visible ON %I.data_source_connections', v_schema);
    EXECUTE format(
        'CREATE POLICY query_parameters_visible ON %I.data_source_connections USING (tenant_id = public.current_tenant_id_safe())',
        v_schema
    );

    -- NEW: pinned_items — private by default, shared rows readable by
    -- anyone in the tenant, writable only by the owner (see header
    -- comment above for exactly why this needs TWO policies, not one).
    EXECUTE format('ALTER TABLE %I.pinned_items ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS pinned_items_owner_full ON %I.pinned_items', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS pinned_items_shared_read ON %I.pinned_items', v_schema);
    EXECUTE format(
        'CREATE POLICY pinned_items_owner_full ON %I.pinned_items FOR ALL USING '
        '(tenant_id = public.current_tenant_id_safe() AND user_id = public.current_user_id_safe())',
        v_schema
    );
    EXECUTE format(
        'CREATE POLICY pinned_items_shared_read ON %I.pinned_items FOR SELECT USING '
        '(tenant_id = public.current_tenant_id_safe() AND is_shared = true)',
        v_schema
    );

    EXECUTE format('GRANT USAGE ON SCHEMA %I TO ryze_app', v_schema);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO ryze_app', v_schema);
END;
$$;

-- ── Backfill: add the column + RLS to every EXISTING tenant's schema ──────
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT id, schema_name FROM public.tenants LOOP
        EXECUTE format('ALTER TABLE %I.pinned_items ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false', t.schema_name);
        PERFORM public.provision_tenant_application_schema(t.id);
    END LOOP;
END;
$$;
