-- ============================================================================
-- Whole-dashboard sharing (replaces per-item share/unshare)
-- ============================================================================
-- Previously, sharing was a flag on each individual pinned item, made
-- visible to the WHOLE tenant. The actual requirement is different:
-- share your ENTIRE dashboard with ONE specific person (by email, must
-- already have a login), not "everyone in the company can see this one
-- card." This is a relationship (who shared their dashboard with whom),
-- not a property of an individual pin — so it gets its own table rather
-- than reusing is_shared.
--
-- The old is_shared column on pinned_items is left in place but no
-- longer drives visibility (dropping it outright would be a bigger,
-- separate migration risk not worth taking for a column that's simply
-- unused going forward) — the RLS policy below is what actually changed.
--
-- Run this after private_dashboards.sql.
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenant_template.dashboard_shares (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID NOT NULL,
    owner_user_id     UUID NOT NULL,   -- whose dashboard is being shared
    shared_with_user_id UUID NOT NULL, -- who can now see it
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (owner_user_id, shared_with_user_id)
);

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
    -- NEW
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.dashboard_shares (LIKE tenant_template.dashboard_shares INCLUDING ALL)', v_schema);

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

    -- CHANGED: pinned_items visibility is now "your own pins" OR "any
    -- pin owned by someone who has shared their WHOLE dashboard with
    -- you" — a correlated subquery against this tenant's own
    -- dashboard_shares table, not the is_shared column anymore. Write
    -- access (the ALL policy) stays owner-only, unchanged.
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
        '(tenant_id = public.current_tenant_id_safe() AND EXISTS ('
        '  SELECT 1 FROM %I.dashboard_shares ds '
        '  WHERE ds.owner_user_id = pinned_items.user_id '
        '    AND ds.shared_with_user_id = public.current_user_id_safe()'
        '))',
        v_schema, v_schema
    );

    -- NEW: dashboard_shares itself — you can see shares you created OR
    -- shares someone made TO you (so you know who's shared with you),
    -- but only the owner can create/revoke a share of their own dashboard.
    EXECUTE format('ALTER TABLE %I.dashboard_shares ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS dashboard_shares_owner_full ON %I.dashboard_shares', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS dashboard_shares_recipient_read ON %I.dashboard_shares', v_schema);
    EXECUTE format(
        'CREATE POLICY dashboard_shares_owner_full ON %I.dashboard_shares FOR ALL USING '
        '(tenant_id = public.current_tenant_id_safe() AND owner_user_id = public.current_user_id_safe())',
        v_schema
    );
    EXECUTE format(
        'CREATE POLICY dashboard_shares_recipient_read ON %I.dashboard_shares FOR SELECT USING '
        '(tenant_id = public.current_tenant_id_safe() AND shared_with_user_id = public.current_user_id_safe())',
        v_schema
    );

    EXECUTE format('GRANT USAGE ON SCHEMA %I TO ryze_app', v_schema);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO ryze_app', v_schema);
END;
$$;

DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT id, schema_name FROM public.tenants LOOP
        PERFORM public.provision_tenant_application_schema(t.id);
    END LOOP;
END;
$$;
