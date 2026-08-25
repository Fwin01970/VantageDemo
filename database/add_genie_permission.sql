-- ============================================================================
-- Ryze Infinity — Genie access permission
-- ============================================================================
-- 'genie:access' is deliberately SEPARATE from 'data:query'. Not every
-- Databricks user should see the dedicated Genie tab — this lets a
-- tenant grant it selectively (e.g. only to users who've been trained
-- on interpreting Genie's generated SQL), while 'data:query' continues
-- to gate the general Ask AI chat's ability to pull data via its tool.
--
-- Run this AFTER seed.sql. For testing, this grants it to Sarah Chen's
-- "Claims Director" role.
-- ============================================================================

INSERT INTO permissions (code, description) VALUES
    ('genie:access', 'Use the dedicated Genie (Databricks NL-to-SQL) tab');

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a1111111-0000-0000-0000-000000000001', id FROM permissions WHERE code = 'genie:access';
