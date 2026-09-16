-- ============================================================================
-- Move Query Parameters (data_source_connections) into each tenant's
-- PRIVATE schema
-- ============================================================================
-- Same reasoning and mechanism as move_genie_config_to_tenant_schema.sql:
-- data_source_resolver.py already reads this table with an UNQUALIFIED
-- name and no tenant_id filter in its SQL (relying entirely on RLS +
-- search_path) — so moving the physical table into each tenant's own
-- schema requires ZERO changes to that function. It will just keep
-- working, resolving to the correct tenant automatically.
--
-- Run this after move_genie_config_to_tenant_schema.sql.
-- ============================================================================

-- ── 1. Template table ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenant_template.data_source_connections (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL,
    platform    TEXT NOT NULL,
    config      JSONB NOT NULL DEFAULT '{}'::jsonb,
    secret_ref  TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ── 2. Extend provisioning (reproduces the full function body again,
--      same as move_genie_config_to_tenant_schema.sql did — CREATE OR
--      REPLACE always replaces the whole thing) ────────────────────────

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
    -- NEW: Query Parameters, same per-tenant treatment as everything above
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

    -- NEW: Query Parameters RLS — every user in the tenant can see it
    -- (it's a shared connection, not personal), same "belt and
    -- suspenders" double-check as everywhere else: even though
    -- search_path already ensures the right physical table is hit, RLS
    -- independently re-confirms tenant_id matches underneath.
    EXECUTE format('ALTER TABLE %I.data_source_connections ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS query_parameters_visible ON %I.data_source_connections', v_schema);
    EXECUTE format(
        'CREATE POLICY query_parameters_visible ON %I.data_source_connections USING (tenant_id = public.current_tenant_id_safe())',
        v_schema
    );

    EXECUTE format('GRANT USAGE ON SCHEMA %I TO ryze_app', v_schema);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO ryze_app', v_schema);
END;
$$;


-- ── 3. Backfill existing tenants + migrate any already-saved config ──────

DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT id, schema_name FROM public.tenants LOOP
        PERFORM public.provision_tenant_application_schema(t.id);

        IF to_regclass('public.data_source_connections') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.data_source_connections SELECT * FROM public.data_source_connections WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON TABLE public.data_source_connections FROM ryze_app;


-- ============================================================================
-- 4. Admin (Super Admin, cross-tenant) functions — rewritten for
--    per-tenant schemas. SAME NAMES AND SIGNATURES as
--    add_admin_extended.sql, so admin.py needs ZERO changes.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_data_source_connection_for_admin(p_tenant_id UUID)
RETURNS TABLE (
    id UUID, platform TEXT, config JSONB, secret_ref TEXT,
    is_active BOOLEAN, created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE tenants.id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT id, platform, config, secret_ref, is_active, created_at FROM %I.data_source_connections '
        'WHERE tenant_id = $1 ORDER BY created_at DESC',
        v_schema
    ) USING p_tenant_id;
END;
$$;

CREATE OR REPLACE FUNCTION upsert_data_source_connection_for_admin(
    p_tenant_id UUID, p_platform TEXT, p_config JSONB,
    p_secret_ref TEXT, p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
    v_id UUID;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    EXECUTE format('SELECT id FROM %I.data_source_connections WHERE tenant_id = $1 AND platform = $2', v_schema)
        INTO v_id USING p_tenant_id, p_platform;

    IF v_id IS NULL THEN
        EXECUTE format(
            'INSERT INTO %I.data_source_connections (tenant_id, platform, config, secret_ref, is_active) '
            'VALUES ($1, $2, $3, $4, $5) RETURNING id',
            v_schema
        ) INTO v_id USING p_tenant_id, p_platform, p_config, p_secret_ref, p_is_active;
    ELSE
        EXECUTE format(
            'UPDATE %I.data_source_connections SET config = $2, secret_ref = $3, is_active = $4 WHERE id = $1',
            v_schema
        ) USING v_id, p_config, p_secret_ref, p_is_active;
    END IF;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_data_source_connection_for_admin(p_connection_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    -- p_connection_id alone doesn't say which tenant's schema it lives
    -- in, so find it by searching every tenant schema for a row with
    -- this id. Small, bounded loop (one iteration per tenant) — fine at
    -- admin-action volume; not used in any hot path.
    FOR v_schema IN SELECT schema_name FROM tenants LOOP
        EXECUTE format('DELETE FROM %I.data_source_connections WHERE id = $1', v_schema) USING p_connection_id;
    END LOOP;
END;
$$;
