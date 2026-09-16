-- ============================================================================
-- Review: exactly who exists in each tenant right now
-- ============================================================================
-- Run this and share the output before deleting anything. The recovery
-- process brought back whatever was in the backup at the time it was
-- taken, which may include more users/roles than the "2 per tenant"
-- target — this shows the real current state so we pick exactly the
-- right ones to remove, not guess.
-- ============================================================================

SELECT
    t.name AS tenant_name,
    u.id AS user_id,
    u.display_name,
    u.email,
    u.is_active,
    u.created_at,
    u.last_login_at,
    array_agg(r.name) AS roles
FROM tenants t
JOIN users u ON u.tenant_id = t.id
LEFT JOIN user_roles ur ON ur.user_id = u.id
LEFT JOIN roles r ON r.id = ur.role_id
GROUP BY t.name, u.id, u.display_name, u.email, u.is_active, u.created_at, u.last_login_at
ORDER BY t.name, u.created_at;

-- Also show every ROLE per tenant (not just per user) — if a tenant has
-- more than one role, that's worth knowing before cleanup too, since
-- the current design intends exactly ONE role ("Team Member") per
-- tenant, held identically by every user in it.
SELECT
    t.name AS tenant_name,
    r.id AS role_id,
    r.name AS role_name,
    array_agg(p.code) AS permissions,
    (SELECT count(*) FROM user_roles ur WHERE ur.role_id = r.id) AS user_count
FROM tenants t
JOIN roles r ON r.tenant_id = t.id
LEFT JOIN role_permissions rp ON rp.role_id = r.id
LEFT JOIN permissions p ON p.id = rp.permission_id
GROUP BY t.name, r.id, r.name
ORDER BY t.name, r.name;
