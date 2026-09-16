-- ============================================================================
-- Move Genie dynamic config (query parameters, template, suggested
-- questions) from public+RLS into each tenant's PRIVATE schema
-- ============================================================================
-- Originally added in add_genie_dynamic_config.sql as public tables with
-- RLS — functionally isolated, but not physically separated the way
-- user_credentials/local_secrets are. Since these rows are explicitly
-- scoped per-user (a specific user_id can override the tenant default),
-- they get the same treatment as credentials: a real, physically
-- separate table per tenant, not a shared table filtered by a column.
--
-- Mechanism is IDENTICAL to how user_credentials was migrated in
-- tenant_application_schemas.sql:
--   1. Template tables live in `tenant_template` (never on any session's
--      search_path, contains no real data).
--   2. provision_tenant_application_schema(tenant_id) clones them into
--      that tenant's own tenant_<uuid> schema.
--   3. An ordinary logged-in user's session already has search_path set
--      to their tenant's schema (get_current_user(), unchanged) — so
--      the SAME unqualified table name automatically reaches a
--      different, private table depending on who's logged in.
--   4. Platform Super Admin write/read functions are cross-tenant by
--      nature, so they use dynamic, schema-qualified SQL (%I) instead of
--      relying on search_path — same style as
--      provision_tenant_application_schema itself already uses.
--
-- Run this after add_genie_dynamic_config.sql and
-- tenant_application_schemas.sql.
-- ============================================================================

-- Defensive: don't assume tenant_template already exists just because
-- tenant_application_schemas.sql is supposed to have run first. If it
-- hasn't (wrong run order, or a database whose history predates that
-- file), this makes the migration self-sufficient instead of failing.
CREATE SCHEMA IF NOT EXISTS tenant_template;

-- ── 1. Template tables ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tenant_template.genie_query_parameter_fields (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL,
    user_id       UUID,                -- NULL = tenant-wide default
    field_name    TEXT NOT NULL,
    options       TEXT[] NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_template.genie_question_templates (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL,
    user_id     UUID,                  -- NULL = tenant-wide default
    template    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tenant_template.genie_suggested_questions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL,
    user_id       UUID,                -- NULL = tenant-wide default
    question_text TEXT NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ── 2. Extend provisioning to also create these 3 tables per tenant ───────
-- CREATE OR REPLACE FUNCTION replaces the WHOLE body, so this reproduces
-- every original statement from tenant_application_schemas.sql plus the
-- 3 new tables — nothing from the original provisioning is dropped.

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
    -- NEW: Genie dynamic config, same per-tenant treatment as everything above
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_query_parameter_fields (LIKE tenant_template.genie_query_parameter_fields INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_question_templates (LIKE tenant_template.genie_question_templates INCLUDING ALL)', v_schema);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.genie_suggested_questions (LIKE tenant_template.genie_suggested_questions INCLUDING ALL)', v_schema);
    -- The unique index backing set_genie_question_template_for_admin's
    -- ON CONFLICT isn't copied by "INCLUDING ALL" from a plain template
    -- table with no index of its own — create it explicitly here, same
    -- expression-based index used in add_genie_dynamic_config.sql.
    -- Index only needs to be unique WITHIN this tenant's own schema
    -- (Postgres namespaces identifiers per-schema), so no tenant prefix
    -- is needed on the name itself — avoids exceeding the 63-character
    -- identifier limit that a tenant-id-prefixed name would hit.
    EXECUTE format(
        'CREATE UNIQUE INDEX IF NOT EXISTS genie_question_templates_scope_idx ON %I.genie_question_templates (tenant_id, COALESCE(user_id, ''00000000-0000-0000-0000-000000000000''))',
        v_schema
    );

    EXECUTE format('ALTER TABLE %I.user_credentials ENABLE ROW LEVEL SECURITY', v_schema);
    EXECUTE format('DROP POLICY IF EXISTS user_owns_credentials ON %I.user_credentials', v_schema);
    EXECUTE format('CREATE POLICY user_owns_credentials ON %I.user_credentials USING (tenant_id = public.current_tenant_id_safe() AND user_id = public.current_user_id_safe())', v_schema);

    -- NEW: Genie config RLS — deliberately DIFFERENT from credentials'
    -- policy. Credentials are ALWAYS personal (no shared default), so
    -- that policy requires an exact user_id match. Genie config has a
    -- real tenant-wide default (user_id IS NULL) that every user in the
    -- tenant must be able to read even though they didn't create it —
    -- so this policy allows a row through if it's EITHER this user's
    -- own override OR nobody's in particular (the shared default).
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

        IF to_regclass('public.genie_query_parameter_fields') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.genie_query_parameter_fields SELECT * FROM public.genie_query_parameter_fields WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.genie_question_templates') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.genie_question_templates SELECT * FROM public.genie_question_templates WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.genie_suggested_questions') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.genie_suggested_questions SELECT * FROM public.genie_suggested_questions WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
    END LOOP;
END;
$$;

-- Same treatment as user_credentials/local_secrets at the end of
-- tenant_application_schemas.sql: the app role loses access to the old
-- shared copies entirely, so there's no leftover path that could
-- accidentally read across tenants. Tables are left in place (not
-- dropped) purely so this migration is reversible if ever needed.
REVOKE ALL ON TABLE public.genie_query_parameter_fields,
                     public.genie_question_templates,
                     public.genie_suggested_questions
FROM ryze_app;


-- ============================================================================
-- 4. Admin (Super Admin, cross-tenant) functions — rewritten for
--    per-tenant schemas. SAME NAMES AND SIGNATURES as
--    add_genie_dynamic_config.sql, so admin.py needs ZERO changes.
-- ============================================================================
-- These are inherently cross-tenant (a Super Admin's own session is
-- scoped to the internal platform tenant, not whatever tenant they're
-- configuring) so they use dynamic, schema-qualified SQL throughout —
-- never search_path — same style provision_tenant_application_schema
-- itself already uses, for the same reason.

CREATE OR REPLACE FUNCTION set_genie_query_parameter_fields_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_fields JSONB
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    EXECUTE format(
        'DELETE FROM %I.genie_query_parameter_fields WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL))',
        v_schema
    ) USING p_tenant_id, p_user_id;

    EXECUTE format(
        'INSERT INTO %I.genie_query_parameter_fields (tenant_id, user_id, field_name, options, display_order) '
        'SELECT $1, $2, elem->>%L, ARRAY(SELECT jsonb_array_elements_text(elem->%L)), '
        'COALESCE((elem->>%L)::INT, ord - 1) '
        'FROM jsonb_array_elements($3) WITH ORDINALITY AS t(elem, ord)',
        v_schema, 'field_name', 'options', 'display_order'
    ) USING p_tenant_id, p_user_id, p_fields;
END;
$$;

CREATE OR REPLACE FUNCTION get_genie_query_parameter_fields_for_admin(p_tenant_id UUID, p_user_id UUID)
RETURNS TABLE (field_name TEXT, options TEXT[], display_order INT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT field_name, options, display_order FROM %I.genie_query_parameter_fields '
        'WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL)) ORDER BY display_order',
        v_schema
    ) USING p_tenant_id, p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION set_genie_question_template_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_template TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    EXECUTE format(
        'INSERT INTO %I.genie_question_templates (tenant_id, user_id, template) VALUES ($1, $2, $3) '
        'ON CONFLICT (tenant_id, COALESCE(user_id, %L)) DO UPDATE SET template = EXCLUDED.template',
        v_schema, '00000000-0000-0000-0000-000000000000'
    ) USING p_tenant_id, p_user_id, p_template;
END;
$$;

CREATE OR REPLACE FUNCTION set_genie_suggested_questions_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_questions TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    EXECUTE format(
        'DELETE FROM %I.genie_suggested_questions WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL))',
        v_schema
    ) USING p_tenant_id, p_user_id;

    EXECUTE format(
        'INSERT INTO %I.genie_suggested_questions (tenant_id, user_id, question_text, display_order) '
        'SELECT $1, $2, q, ord - 1 FROM unnest($3::text[]) WITH ORDINALITY AS t(q, ord)',
        v_schema
    ) USING p_tenant_id, p_user_id, p_questions;
END;
$$;

CREATE OR REPLACE FUNCTION get_genie_config_for_admin(p_tenant_id UUID, p_user_id UUID)
RETURNS TABLE (fields JSONB, template TEXT, suggested_questions TEXT[])
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
    v_schema TEXT;
BEGIN
    SELECT schema_name INTO v_schema FROM tenants WHERE id = p_tenant_id;
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'Unknown tenant %', p_tenant_id;
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT '
        '  COALESCE((SELECT jsonb_agg(jsonb_build_object(%L, field_name, %L, options) ORDER BY display_order) '
        '            FROM %I.genie_query_parameter_fields '
        '            WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL))), ''[]''::jsonb), '
        '  (SELECT template FROM %I.genie_question_templates '
        '   WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL))), '
        '  COALESCE((SELECT array_agg(question_text ORDER BY display_order) FROM %I.genie_suggested_questions '
        '            WHERE tenant_id = $1 AND (user_id = $2 OR (user_id IS NULL AND $2 IS NULL))), ''{}'')',
        'field_name', 'options', v_schema, v_schema, v_schema
    ) USING p_tenant_id, p_user_id;
END;
$$;
