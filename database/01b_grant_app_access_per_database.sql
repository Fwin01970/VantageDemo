-- ============================================================================
-- Give the app login access to THIS database
-- ============================================================================
-- Run this once on EVERY database — the platform database, and every
-- single tenant database, right after creating it (and after running
-- 00_create_app_login_RUN_ONCE.sql, just once, first).
--
-- Unlike the login itself, table/schema permissions ARE per-database,
-- so this part genuinely does need to be repeated for each one.
-- ============================================================================

GRANT USAGE ON SCHEMA public TO ryze_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ryze_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ryze_app;
