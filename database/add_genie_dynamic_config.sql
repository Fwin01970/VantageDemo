-- ============================================================================
-- Ryze Infinity — Dynamic Genie configuration (query parameters,
-- question template, suggested questions)
-- ============================================================================
-- GeniePage.tsx previously hardcoded PRODUCT_LINES/REGIONS/FOCUS_AREAS and
-- a "claims and loss ratio" question template directly in the component —
-- insurance-specific vocabulary that doesn't exist in other industries
-- (e.g. a retail or banking tenant has no "claims" at all). This migration
-- replaces every one of those with rows a Platform Super Admin manages.
--
-- Scoping follows the SAME "personal overrides tenant-wide default"
-- pattern already proven for Databricks/LLM credentials
-- (services/data_source_resolver.py, CREDENTIAL_MANAGEMENT_DESIGN.md):
-- a NULL user_id row is the tenant's default; a specific user_id row is
-- that one person's override. A tenant with no personal override for a
-- user just falls back to its own tenant-wide rows — nobody sees empty
-- dropdowns just because they've never been individually configured.
--
-- Run this after add_admin_extended.sql.
-- ============================================================================

CREATE TABLE genie_query_parameter_fields (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id       UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL = tenant-wide default
    field_name    TEXT NOT NULL,      -- e.g. 'Product line', 'Store', 'Category' — no fixed vocabulary
    options       TEXT[] NOT NULL,    -- the dropdown's choices, in this domain's own terms
    display_order INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE genie_question_templates (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,   -- NULL = tenant-wide default
    template    TEXT NOT NULL   -- e.g. "Show total claims and loss ratio for {Product line} {Analysis focus} in the {Region} region"
                                  -- placeholders are literal field_name values from
                                  -- genie_query_parameter_fields, wrapped in { }
);

-- A plain UNIQUE(tenant_id, user_id) table constraint can't express "at
-- most one tenant-wide default" because Postgres treats every NULL as
-- distinct from every other NULL, so two NULL user_id rows for the same
-- tenant wouldn't violate a normal unique constraint. Coalescing NULL to
-- a fixed sentinel UUID here makes "no override" itself a comparable
-- value, so ON CONFLICT below can target it directly.
CREATE UNIQUE INDEX genie_question_templates_scope_idx
    ON genie_question_templates (tenant_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'));

CREATE TABLE genie_suggested_questions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id       UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL = tenant-wide default
    question_text TEXT NOT NULL,
    display_order INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE genie_query_parameter_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE genie_question_templates     ENABLE ROW LEVEL SECURITY;
ALTER TABLE genie_suggested_questions    ENABLE ROW LEVEL SECURITY;

-- Normal per-request sessions (any logged-in user asking Genie a
-- question) read these directly — no SECURITY DEFINER needed here,
-- because a user reading their OWN tenant's config is exactly what RLS
-- is meant to allow, same as use_cases already works today.
CREATE POLICY tenant_isolation_genie_fields ON genie_query_parameter_fields
    USING (tenant_id = current_tenant_id_safe());
CREATE POLICY tenant_isolation_genie_templates ON genie_question_templates
    USING (tenant_id = current_tenant_id_safe());
CREATE POLICY tenant_isolation_genie_suggestions ON genie_suggested_questions
    USING (tenant_id = current_tenant_id_safe());


-- ============================================================================
-- SECURITY DEFINER functions for the Super Admin side (cross-tenant writes)
-- ============================================================================
-- Same pattern as every other admin.py function: the Platform Super
-- Admin's own session is scoped to the internal platform tenant, so
-- configuring some OTHER tenant's Genie setup needs a narrow,
-- purpose-built bypass — never a blanket one.

-- Replaces ALL fields for a given tenant (+ optional user override) in
-- one call — same "replace the whole set" approach already used for
-- set_role_permissions_for_admin, so the admin UI's save button behaves
-- consistently everywhere: what's on screen becomes exactly what's saved.
CREATE OR REPLACE FUNCTION set_genie_query_parameter_fields_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_fields JSONB
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM genie_query_parameter_fields
    WHERE tenant_id = p_tenant_id
      AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL));

    INSERT INTO genie_query_parameter_fields (tenant_id, user_id, field_name, options, display_order)
    SELECT p_tenant_id, p_user_id,
           elem->>'field_name',
           ARRAY(SELECT jsonb_array_elements_text(elem->'options')),
           COALESCE((elem->>'display_order')::INT, ord - 1)
    FROM jsonb_array_elements(p_fields) WITH ORDINALITY AS t(elem, ord);
END;
$$;

CREATE OR REPLACE FUNCTION get_genie_query_parameter_fields_for_admin(p_tenant_id UUID, p_user_id UUID)
RETURNS TABLE (field_name TEXT, options TEXT[], display_order INT)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT field_name, options, display_order
    FROM genie_query_parameter_fields
    WHERE tenant_id = p_tenant_id
      AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL))
    ORDER BY display_order;
$$;

CREATE OR REPLACE FUNCTION set_genie_question_template_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_template TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO genie_question_templates (tenant_id, user_id, template)
    VALUES (p_tenant_id, p_user_id, p_template)
    ON CONFLICT (tenant_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'))
    DO UPDATE SET template = EXCLUDED.template;
END;
$$;

CREATE OR REPLACE FUNCTION set_genie_suggested_questions_for_admin(
    p_tenant_id UUID, p_user_id UUID, p_questions TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM genie_suggested_questions
    WHERE tenant_id = p_tenant_id
      AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL));

    INSERT INTO genie_suggested_questions (tenant_id, user_id, question_text, display_order)
    SELECT p_tenant_id, p_user_id, q, ord - 1
    FROM unnest(p_questions) WITH ORDINALITY AS t(q, ord);
END;
$$;

-- Full config read for the admin UI (fields + template + suggestions in
-- one call, same shape the runtime GET /data/genie-config endpoint
-- returns to an ordinary logged-in user, just cross-tenant-capable here).
CREATE OR REPLACE FUNCTION get_genie_config_for_admin(p_tenant_id UUID, p_user_id UUID)
RETURNS TABLE (fields JSONB, template TEXT, suggested_questions TEXT[])
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT
        COALESCE((
            SELECT jsonb_agg(jsonb_build_object('field_name', field_name, 'options', options) ORDER BY display_order)
            FROM genie_query_parameter_fields
            WHERE tenant_id = p_tenant_id AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL))
        ), '[]'::jsonb),
        (
            SELECT template FROM genie_question_templates
            WHERE tenant_id = p_tenant_id AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL))
        ),
        COALESCE((
            SELECT array_agg(question_text ORDER BY display_order)
            FROM genie_suggested_questions
            WHERE tenant_id = p_tenant_id AND (user_id = p_user_id OR (user_id IS NULL AND p_user_id IS NULL))
        ), '{}');
$$;
