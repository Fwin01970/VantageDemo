-- ============================================================================
-- Per-tenant PostgreSQL application schemas
-- ============================================================================
-- Keep identity, authentication, RBAC, credentials, data-source metadata,
-- and centralized audit data in public. Move tenant application data into a
-- schema derived from the immutable tenant UUID. The backend sets search_path
-- to "tenant_<uuid>" followed by public after authentication.
--
-- Run after the existing schema/migration files using the ryze_app role's
-- owner/admin connection for the DDL portion.
-- ============================================================================

ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS schema_name TEXT;

UPDATE public.tenants
SET schema_name = 'tenant_' || replace(id::text, '-', '')
WHERE schema_name IS NULL OR schema_name = '';

ALTER TABLE public.tenants ALTER COLUMN schema_name SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tenants_schema_name ON public.tenants (schema_name);

-- A template is used for automatic provisioning of future tenants. It is
-- never placed on an application's search_path and contains no tenant data.
CREATE SCHEMA IF NOT EXISTS tenant_template;

CREATE TABLE IF NOT EXISTS tenant_template.use_cases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    sample_question TEXT NOT NULL,
    icon_key TEXT NOT NULL DEFAULT 'trending-up',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    generated_sql TEXT
);

CREATE TABLE IF NOT EXISTS tenant_template.pinned_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    source TEXT NOT NULL,
    item_type TEXT NOT NULL,
    title TEXT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_template.chat_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    title TEXT NOT NULL DEFAULT 'New conversation',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_template.chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    chart_data JSONB
);

CREATE TABLE IF NOT EXISTS tenant_template.governance_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID,
    question TEXT NOT NULL,
    check_type TEXT NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending',
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    decision_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_template.schema_annotations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    catalog_name TEXT NOT NULL,
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    column_name TEXT,
    note TEXT NOT NULL,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO ryze_app', v_schema);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO ryze_app', v_schema);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_tenant_application_schema_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
    IF NEW.schema_name IS NULL OR NEW.schema_name = '' THEN
        NEW.schema_name := 'tenant_' || replace(NEW.id::text, '-', '');
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.provision_tenant_application_schema_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
    PERFORM public.provision_tenant_application_schema(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenants_set_application_schema_name ON public.tenants;
CREATE TRIGGER tenants_set_application_schema_name
BEFORE INSERT ON public.tenants
FOR EACH ROW EXECUTE FUNCTION public.set_tenant_application_schema_name();

DROP TRIGGER IF EXISTS tenants_provision_application_schema ON public.tenants;
CREATE TRIGGER tenants_provision_application_schema
AFTER INSERT ON public.tenants
FOR EACH ROW EXECUTE FUNCTION public.provision_tenant_application_schema_trigger();

DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT id, schema_name FROM public.tenants LOOP
        PERFORM public.provision_tenant_application_schema(t.id);

        IF to_regclass('public.use_cases') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.use_cases SELECT * FROM public.use_cases WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.pinned_items') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.pinned_items SELECT * FROM public.pinned_items WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.chat_conversations') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.chat_conversations SELECT * FROM public.chat_conversations WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.chat_messages') IS NOT NULL AND to_regclass('public.chat_conversations') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.chat_messages SELECT m.* FROM public.chat_messages m JOIN public.chat_conversations c ON c.id = m.conversation_id WHERE c.tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.governance_reviews') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.governance_reviews SELECT * FROM public.governance_reviews WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
        IF to_regclass('public.schema_annotations') IS NOT NULL THEN
            EXECUTE format(
                'INSERT INTO %I.schema_annotations SELECT * FROM public.schema_annotations WHERE tenant_id = $1 ON CONFLICT (id) DO NOTHING',
                t.schema_name
            ) USING t.id;
        END IF;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.provision_tenant_application_schema(UUID) TO ryze_app;
GRANT USAGE ON SCHEMA tenant_template TO ryze_app;
REVOKE ALL ON SCHEMA tenant_template FROM PUBLIC;
