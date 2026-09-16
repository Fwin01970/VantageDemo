-- ============================================================================
-- Fix tenant user symmetry: exactly 2 users per demo tenant, identical
-- access — no "admin vs viewer" tier within a tenant anymore
-- ============================================================================
-- seed.sql originally gave ABC Insurance an asymmetric pair (Sarah Chen /
-- "Claims Director" with tenant:manage+audit:view, "Demo Viewer" with only
-- data:query) and gave XYZ Bank only ONE user. Per the current
-- requirement, tenant-level user management is Platform Admin's job only
-- (see database/add_platform_admin.sql, add_admin_extended.sql) — there's
-- no reason for one ordinary tenant user to have more power than another
-- within the same company anymore. This migration:
--   1. Collapses both tenants down to a single UNIFIED role each, with
--      identical permissions, and reassigns both existing users to it.
--   2. Adds XYZ Bank's missing second demo user.
--   3. Removes the old two-tier roles entirely so they can't be
--      accidentally reused.
--   4. Grants the Platform Super Admin role 'data:query' — needed so a
--      Super Admin session actually sees the Ask AI tab, per the Master
--      Admin nav requirement (Ask AI / Dashboard / Admin only — NOT
--      Genie or Use Cases, so genie:access/tenant:manage are
--      deliberately NOT added here).
--
-- Run this after add_genie_permission.sql and add_platform_admin.sql.
-- ============================================================================

-- ── ABC Insurance: one unified role for both existing users ───────────────
-- Reuse the existing 'Claims Director' role row (already has data:query +
-- genie:access from seed.sql / add_genie_permission.sql) rather than
-- creating a new one, and simply top it up to the full tenant permission
-- set — avoids leaving an orphaned role id anywhere that might still be
-- referenced.
UPDATE roles SET name = 'Team Member', description = 'Full access for this tenant — every user has the same permissions'
WHERE id = 'a1111111-0000-0000-0000-000000000001';

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a1111111-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('tenant:manage', 'audit:view', 'governance:manage')
ON CONFLICT DO NOTHING;

-- Move the second user off the old "Viewer" role onto the same unified one
DELETE FROM user_roles
WHERE user_id = 'b1111111-0000-0000-0000-000000000002'
  AND role_id = 'a1111111-0000-0000-0000-000000000002';

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b1111111-0000-0000-0000-000000000002', 'a1111111-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- The old two-tier "Viewer" role is no longer used by anyone — remove it
-- entirely so it can't be accidentally re-granted later.
DELETE FROM role_permissions WHERE role_id = 'a1111111-0000-0000-0000-000000000002';
DELETE FROM roles WHERE id = 'a1111111-0000-0000-0000-000000000002';


-- ── XYZ Bank: top up the existing role, add the missing second user ───────
UPDATE roles SET name = 'Team Member', description = 'Full access for this tenant — every user has the same permissions'
WHERE id = 'a2222222-0000-0000-0000-000000000001';

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('genie:access', 'tenant:manage', 'audit:view', 'governance:manage')
ON CONFLICT DO NOTHING;

INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222',
     'priya.patel@xyzbank.demo', 'Priya Patel')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b2222222-0000-0000-0000-000000000002', 'a2222222-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;


-- ── Platform Super Admin: add data:query so Ask AI is visible ─────────────
-- Deliberately NOT genie:access or tenant:manage — the Master Admin nav
-- shows exactly Ask AI, Dashboard, Admin, nothing else.
INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001', id FROM permissions WHERE code = 'data:query'
ON CONFLICT DO NOTHING;
