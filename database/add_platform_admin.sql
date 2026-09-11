-- ============================================================================
-- Ryze Infinity — Platform Admin: permission, demo identity, and functions
-- ============================================================================
-- This file was MISSING from the project even though backend/app/routers/
-- admin.py already called three of these functions (list_all_companies_
-- for_admin, create_company_for_admin, create_user_for_admin) and gated
-- every endpoint on a 'platform:manage' permission that was never actually
-- inserted anywhere. Without this file, the Admin tab fails at runtime the
-- moment anyone calls it, and no demo user could ever have held
-- 'platform:manage' to test it with.
--
-- This migration:
--   1. Adds the 'platform:manage' permission.
--   2. Creates a dedicated INTERNAL tenant + role + demo user to hold it —
--      deliberately NOT one of the real demo customer tenants (ABC
--      Insurance / XYZ Bank), matching admin.py's own docstring claim that
--      platform:manage is separate from any customer's tenant:manage.
--   3. Defines every SECURITY DEFINER function the (now full-CRUD) admin
--      router needs — the original 3, plus update/disable/enable/delete
--      for both tenants and users, plus password reset.
--
-- Run this once, after schema.sql + seed.sql, as the postgres superuser
-- (same as every other add_*.sql file in this folder).
-- ============================================================================

INSERT INTO permissions (code, description) VALUES
    ('platform:manage', 'Create/update/disable/delete tenants and users; platform-wide monitoring')
ON CONFLICT (code) DO NOTHING;

-- ── A dedicated internal tenant to hold platform-operator accounts ────────
-- Every user row must belong to exactly one tenant (schema.sql's NOT NULL
-- FK), so a platform admin still needs a tenant row to sit under — this
-- one is clearly marked 'internal', is never shown as a real customer
-- anywhere in the UI (nothing in the app queries tenants without also
-- filtering to what the logged-in user themselves belongs to), and exists
-- purely so platform:manage has somewhere real to live for local testing.
INSERT INTO tenants (id, name, industry, is_active) VALUES
    ('00000000-0000-0000-0000-000000000000', 'Ryze Infinity (Platform)', 'internal', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
     'Platform Super Admin', 'Full platform administration access — tenant/user lifecycle, monitoring')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT '00000000-0000-0000-0000-000000000001', id FROM permissions WHERE code = 'platform:manage'
ON CONFLICT DO NOTHING;

INSERT INTO users (id, tenant_id, email, display_name, is_active) VALUES
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
     'platform.admin@ryzeinfinity.demo', 'Platform Super Admin', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- list_demo_users_for_login() (schema.sql) is a plain query over all
-- active users in active tenants, so this new user shows up in the demo
-- login picker automatically — nothing else to wire up for local testing.


-- ============================================================================
-- SECURITY DEFINER functions
-- ============================================================================
-- Same deliberate, narrow RLS-bypass pattern already used elsewhere in this
-- project (see schema.sql's list_demo_users_for_login and
-- add_password_and_oauth_auth.sql's login-lookup functions): these need to
-- read/write across tenants, which normal RLS-scoped queries can't do by
-- design. Every caller is still gated by require_permission("platform:manage")
-- in Python BEFORE any of these ever runs — RLS is bypassed only for this
-- one narrow purpose, never anywhere else.
-- ============================================================================

-- ── Tenants ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION list_all_companies_for_admin()
RETURNS TABLE (
    id UUID, name TEXT, industry TEXT, is_active BOOLEAN,
    created_at TIMESTAMPTZ, user_count BIGINT
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT t.id, t.name, t.industry, t.is_active, t.created_at,
           COUNT(u.id) AS user_count
    FROM tenants t
    LEFT JOIN users u ON u.tenant_id = t.id
    GROUP BY t.id
    ORDER BY t.name;
$$;

CREATE OR REPLACE FUNCTION create_company_for_admin(p_name TEXT, p_industry TEXT)
RETURNS UUID
LANGUAGE sql SECURITY DEFINER AS $$
    INSERT INTO tenants (name, industry) VALUES (p_name, p_industry)
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION update_company_for_admin(p_tenant_id UUID, p_name TEXT, p_industry TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE tenants SET name = p_name, industry = p_industry WHERE id = p_tenant_id;
$$;

CREATE OR REPLACE FUNCTION set_company_active_for_admin(p_tenant_id UUID, p_is_active BOOLEAN)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE tenants SET is_active = p_is_active WHERE id = p_tenant_id;
$$;

CREATE OR REPLACE FUNCTION delete_company_for_admin(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Refuse to delete the internal platform tenant itself, even by a
    -- platform admin — deleting the tenant that holds every
    -- platform:manage account would lock every admin out at once.
    IF p_tenant_id = '00000000-0000-0000-0000-000000000000' THEN
        RAISE EXCEPTION 'Cannot delete the internal platform tenant';
    END IF;
    -- users/roles/data_source_connections/audit_log all cascade via their
    -- existing ON DELETE CASCADE foreign keys to tenants (schema.sql) —
    -- this delete alone is sufficient.
    DELETE FROM tenants WHERE id = p_tenant_id;
END;
$$;

-- ── Users ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION list_all_users_for_admin()
RETURNS TABLE (
    id UUID, tenant_id UUID, tenant_name TEXT, display_name TEXT, email TEXT,
    is_active BOOLEAN, created_at TIMESTAMPTZ, last_login_at TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT u.id, u.tenant_id, t.name, u.display_name, u.email,
           u.is_active, u.created_at, u.last_login_at
    FROM users u
    JOIN tenants t ON t.id = u.tenant_id
    ORDER BY t.name, u.display_name;
$$;

CREATE OR REPLACE FUNCTION create_user_for_admin(p_tenant_id UUID, p_display_name TEXT, p_email TEXT)
RETURNS UUID
LANGUAGE sql SECURITY DEFINER AS $$
    INSERT INTO users (tenant_id, display_name, email) VALUES (p_tenant_id, p_display_name, p_email)
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION update_user_for_admin(p_user_id UUID, p_display_name TEXT, p_email TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE users SET display_name = p_display_name, email = p_email WHERE id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION set_user_active_for_admin(p_user_id UUID, p_is_active BOOLEAN)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE users SET is_active = p_is_active WHERE id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION delete_user_for_admin(p_user_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    DELETE FROM users WHERE id = p_user_id;
$$;

-- Password reset: the hash itself is computed in Python (reusing the
-- existing backend/app/auth/password.py::hash_password — the same
-- bcrypt context already used for real email/password login), so this
-- function's only job is writing an already-hashed value across the
-- tenant boundary. It also clears any account lock and forces
-- auth_provider back to 'local', so a reset always results in a
-- password-loginable account even if it was previously OAuth-only or locked.
CREATE OR REPLACE FUNCTION set_user_password_for_admin(p_user_id UUID, p_password_hash TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE users
    SET password_hash = p_password_hash,
        auth_provider = 'local',
        failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = p_user_id;
$$;
