-- ============================================================================
-- Ryze Infinity — Platform Admin, extended: Roles, Query Parameters, Audit
-- ============================================================================
-- Adds the SECURITY DEFINER functions the admin portal needs for:
--   - Role management (create/update/delete roles, assign permissions,
--     assign/remove roles from users) — scoped to a specific tenant.
--   - "Query Parameters" = data_source_connections (host, warehouse,
--     catalog, secret_ref) — add or edit a tenant's shared Databricks
--     connection details from the admin UI instead of hand-editing SQL
--     (this replaces the old manual update_databricks_connection.sql
--     workflow with a real, repeatable admin action).
--   - Audit log, filterable by tenant and/or user, across tenants — the
--     normal audit_log RLS policy only lets a session see its OWN
--     tenant's rows, which is correct for every other part of the app but
--     wrong for a platform admin who needs to look at ANY tenant's log.
--
-- Deliberately does NOT touch anything related to Ask AI / Genie / Use
-- Cases — the Master Admin portal manages platform structure (who exists,
-- what they're allowed to do, what they connect to), not product content.
--
-- Run this after add_platform_admin.sql.
-- ============================================================================

-- ── Roles ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION list_roles_for_admin(p_tenant_id UUID)
RETURNS TABLE (
    id UUID, name TEXT, description TEXT,
    permission_codes TEXT[], user_count BIGINT
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT r.id, r.name, r.description,
           COALESCE(array_agg(DISTINCT p.code) FILTER (WHERE p.code IS NOT NULL), '{}'),
           COUNT(DISTINCT ur.user_id)
    FROM roles r
    LEFT JOIN role_permissions rp ON rp.role_id = r.id
    LEFT JOIN permissions p ON p.id = rp.permission_id
    LEFT JOIN user_roles ur ON ur.role_id = r.id
    WHERE r.tenant_id = p_tenant_id
    GROUP BY r.id
    ORDER BY r.name;
$$;

CREATE OR REPLACE FUNCTION list_all_permissions_for_admin()
RETURNS TABLE (id UUID, code TEXT, description TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
    -- permissions is a shared, non-tenant catalog (schema.sql's own
    -- comment says so) — this doesn't strictly need SECURITY DEFINER
    -- since it isn't RLS-protected, but it's kept here so every admin
    -- database call goes through this same file's consistent pattern.
    SELECT id, code, description FROM permissions ORDER BY code;
$$;

CREATE OR REPLACE FUNCTION create_role_for_admin(p_tenant_id UUID, p_name TEXT, p_description TEXT)
RETURNS UUID
LANGUAGE sql SECURITY DEFINER AS $$
    INSERT INTO roles (tenant_id, name, description) VALUES (p_tenant_id, p_name, p_description)
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION update_role_for_admin(p_role_id UUID, p_name TEXT, p_description TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE roles SET name = p_name, description = p_description WHERE id = p_role_id;
$$;

CREATE OR REPLACE FUNCTION delete_role_for_admin(p_role_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    DELETE FROM roles WHERE id = p_role_id;
$$;

-- Replaces a role's ENTIRE permission set with exactly the codes given —
-- simpler and less error-prone for an admin UI (a checklist of
-- permissions with some ticked) than separate add/remove calls that
-- could drift out of sync with what's shown on screen.
CREATE OR REPLACE FUNCTION set_role_permissions_for_admin(p_role_id UUID, p_permission_codes TEXT[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    DELETE FROM role_permissions WHERE role_id = p_role_id;
    INSERT INTO role_permissions (role_id, permission_id)
    SELECT p_role_id, id FROM permissions WHERE code = ANY(p_permission_codes);
END;
$$;

CREATE OR REPLACE FUNCTION assign_role_to_user_for_admin(p_user_id UUID, p_role_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    INSERT INTO user_roles (user_id, role_id) VALUES (p_user_id, p_role_id)
    ON CONFLICT DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION remove_role_from_user_for_admin(p_user_id UUID, p_role_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    DELETE FROM user_roles WHERE user_id = p_user_id AND role_id = p_role_id;
$$;

CREATE OR REPLACE FUNCTION list_roles_for_user_for_admin(p_user_id UUID)
RETURNS TABLE (role_id UUID, role_name TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT r.id, r.name FROM roles r
    JOIN user_roles ur ON ur.role_id = r.id
    WHERE ur.user_id = p_user_id
    ORDER BY r.name;
$$;


-- ── "Query Parameters" — per-tenant shared data source connection ─────────
-- This is the same data_source_connections table
-- services/data_source_resolver.py already reads from as the tenant-wide
-- fallback connection. Today the ONLY way to set it is by hand-editing
-- SQL (see update_databricks_connection.sql) — these functions let the
-- admin UI do the same thing as a real, repeatable action instead.

CREATE OR REPLACE FUNCTION get_data_source_connection_for_admin(p_tenant_id UUID)
RETURNS TABLE (
    id UUID, platform TEXT, config JSONB, secret_ref TEXT,
    is_active BOOLEAN, created_at TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT id, platform, config, secret_ref, is_active, created_at
    FROM data_source_connections
    WHERE tenant_id = p_tenant_id
    ORDER BY created_at DESC;
$$;

-- One row per (tenant, platform): updates in place if a connection for
-- this tenant+platform already exists, otherwise inserts a new one —
-- matches "add query parameters... or edit previously added" exactly.
CREATE OR REPLACE FUNCTION upsert_data_source_connection_for_admin(
    p_tenant_id UUID, p_platform TEXT, p_config JSONB,
    p_secret_ref TEXT, p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM data_source_connections
    WHERE tenant_id = p_tenant_id AND platform = p_platform;

    IF v_id IS NULL THEN
        INSERT INTO data_source_connections (tenant_id, platform, config, secret_ref, is_active)
        VALUES (p_tenant_id, p_platform, p_config, p_secret_ref, p_is_active)
        RETURNING id INTO v_id;
    ELSE
        UPDATE data_source_connections
        SET config = p_config, secret_ref = p_secret_ref, is_active = p_is_active
        WHERE id = v_id;
    END IF;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_data_source_connection_for_admin(p_connection_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER AS $$
    DELETE FROM data_source_connections WHERE id = p_connection_id;
$$;


-- ── Audit log — tenant-wise and user-wise, across tenants ─────────────────
-- p_tenant_id and p_user_id are both optional: pass just a tenant to see
-- everyone's activity in that company, pass both to narrow to one
-- person, or pass neither for a full platform-wide feed (paginate with
-- p_limit/p_offset since this can get large).

CREATE OR REPLACE FUNCTION list_audit_log_for_admin(
    p_tenant_id UUID DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 200,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID, tenant_id UUID, tenant_name TEXT,
    user_id UUID, user_display_name TEXT,
    action TEXT, details JSONB, created_at TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT a.id, a.tenant_id, t.name, a.user_id, u.display_name,
           a.action, a.details, a.created_at
    FROM audit_log a
    JOIN tenants t ON t.id = a.tenant_id
    LEFT JOIN users u ON u.id = a.user_id
    WHERE (p_tenant_id IS NULL OR a.tenant_id = p_tenant_id)
      AND (p_user_id IS NULL OR a.user_id = p_user_id)
    ORDER BY a.created_at DESC
    LIMIT p_limit OFFSET p_offset;
$$;
