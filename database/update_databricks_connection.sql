-- ============================================================================
-- Ryze Infinity — XYZ Bank's real Databricks connection
-- ============================================================================
-- Run this against your Postgres database (pgAdmin Query Tool, or
-- psql -U postgres -d ryze_infinity -f database/update_databricks_connection.sql).
--
-- The actual token is NOT stored here — it stays in backend/app/.env,
-- this row just points at it BY NAME via secret_ref.
-- ============================================================================

UPDATE data_source_connections
SET
    config = jsonb_build_object(
        'host', 'adb-7405615490948816.16.azuredatabricks.net',
        'warehouse_id', 'f7bdf4d73ce15842',
        'catalog', 'deplearning',
        'schema', 'Gold'
    ),
    secret_ref = 'DATABRICKS_PAT',
    platform = 'databricks',
    is_active = true
WHERE tenant_id = '22222222-2222-2222-2222-222222222222'  -- XYZ Bank (Demo)
  AND platform IN ('databricks', 'local_demo');
