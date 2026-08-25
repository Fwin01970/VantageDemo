-- ============================================================================
-- Ryze Infinity — Set ABC Insurance's real Databricks connection
-- ============================================================================
-- This fills in NON-SECRET connection details for one tenant. The actual
-- Personal Access Token is NOT stored here — it stays in backend/.env,
-- and this row just points at it by name via secret_ref.
--
-- Only ABC Insurance gets a real connection here. XYZ Bank's row is left
-- inactive on purpose — this is what proves the connection is genuinely
-- per-tenant: logging in as James Okafor (XYZ Bank) should get a clean
-- "not configured for your company" message, not access to ABC's data.
--
-- Replace the placeholder values below with your real (non-secret)
-- details before running this.
-- ============================================================================

UPDATE data_source_connections
SET
    config = jsonb_build_object(
        'host', 'dbc-ef772806-308c.cloud.databricks.com',
        'warehouse_id', 'ec94e5287125e125',
        'genie_space_id', '01f0baaeb8c215c4ba992f3d177bd339',
        'catalog', 'poc_alliedworld',
        'schema', 'curated_gold'
    ),
    secret_ref = 'DATABRICKS_PAT',   -- name of the .env variable holding the real token
    is_active = true
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'  -- ABC Insurance (Demo)
  AND platform = 'databricks';
