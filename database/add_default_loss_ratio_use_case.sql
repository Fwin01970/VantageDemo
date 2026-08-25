-- ============================================================================
-- Default "Loss ratio" use case for every tenant
-- ============================================================================
-- Loss ratio started as an insurance-only preset (tenant
-- 11111111-1111-1111-1111-111111111111 only). In practice it's a useful
-- baseline metric to have available regardless of industry — this makes
-- it a standard default for every tenant, not just insurance ones.
--
-- SECURITY DEFINER because a caller creating a brand-new tenant (in
-- admin.py) is acting from THEIR OWN tenant context, but needs to insert
-- a row for the tenant that was just created — a normal RLS-scoped
-- INSERT would be rejected (tenant_id wouldn't match the caller's own
-- current_tenant_id_safe()). Same pattern already used for
-- create_company_for_admin().
-- ============================================================================

CREATE OR REPLACE FUNCTION seed_default_use_cases_for_tenant(p_tenant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO use_cases (tenant_id, title, description, category, sample_question, icon_key)
    SELECT
        p_tenant_id,
        'Loss ratio trend',
        'Compare loss ratio across regions and product lines — a useful baseline metric regardless of industry.',
        'Risk',
        'Show me the loss ratio trend for this year',
        'trending-up'
    WHERE NOT EXISTS (
        SELECT 1 FROM use_cases WHERE tenant_id = p_tenant_id AND title = 'Loss ratio trend'
    );
END;
$$;

-- Backfill every EXISTING tenant (including non-insurance ones, like the
-- banking demo tenant that never had this) — new tenants get it going
-- forward via the call added to admin.py's create_company endpoint.
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT id FROM tenants LOOP
        PERFORM seed_default_use_cases_for_tenant(t.id);
    END LOOP;
END;
$$;
