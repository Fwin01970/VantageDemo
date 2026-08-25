-- ============================================================================
-- Ryze Infinity — Application Metadata Schema
-- ============================================================================
-- This creates the "blank workbook" tables described in the architecture doc:
-- Tenants, Users, Roles, Permissions, Data Source Connections, Audit Log.
--
-- Run this once against a fresh database (instructions in README.md).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- lets Postgres generate unique IDs for us

-- ── Tenants ──────────────────────────────────────────────────────────────
-- One row per client company (e.g. "ABC Insurance", "XYZ Bank").
-- Nothing about industry, branding, or data platform is hardcoded in app
-- code anywhere — it all lives here and is looked up at request time.
CREATE TABLE tenants (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    industry        TEXT NOT NULL,             -- e.g. 'insurance', 'banking'
    entra_tenant_id TEXT,                      -- filled in once real Entra ID exists
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Users ────────────────────────────────────────────────────────────────
-- One row per person. Every user belongs to exactly one tenant.
CREATE TABLE users (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email            TEXT NOT NULL UNIQUE,
    display_name     TEXT NOT NULL,
    entra_object_id  TEXT,                     -- filled in once real Entra ID exists
    is_active        BOOLEAN NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Roles ────────────────────────────────────────────────────────────────
-- Each tenant can define its own roles (e.g. "Claims Director", "Analyst").
-- Roles are NOT hardcoded in app code — they're rows in this table.
CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

-- ── Permissions ──────────────────────────────────────────────────────────
-- A fixed catalog of actions the system understands, e.g. 'data:query',
-- 'tenant:manage'. Not tenant-specific — every tenant picks from this list
-- when building their roles.
CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        TEXT NOT NULL UNIQUE,          -- e.g. 'data:query'
    description TEXT NOT NULL
);

-- ── Role <-> Permission (many-to-many) ──────────────────────────────────
CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ── User <-> Role (many-to-many) ────────────────────────────────────────
CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- ── Data Source Connections ─────────────────────────────────────────────
-- Placeholder for "which Databricks/Snowflake workspace does this tenant
-- use." No real credentials go here directly — config JSON holds
-- non-secret details (host, catalog, schema); secret_ref is a pointer to
-- wherever the real credential will eventually live (a secrets manager).
-- Empty/placeholder for now since we have no real Databricks yet.
CREATE TABLE data_source_connections (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    platform    TEXT NOT NULL,                 -- 'databricks' | 'snowflake' | ...
    config      JSONB NOT NULL DEFAULT '{}',   -- host, catalog, schema, warehouse_id
    secret_ref  TEXT,                          -- pointer to secret, never the secret itself
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Audit Log ────────────────────────────────────────────────────────────
-- Every meaningful action gets a row here, tagged by tenant.
CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users(id),
    action      TEXT NOT NULL,                 -- e.g. 'login', 'query.executed'
    details     JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- ROW-LEVEL SECURITY (second, database-enforced layer of tenant isolation)
-- ============================================================================
-- Even if application code has a bug, Postgres itself will refuse to return
-- rows belonging to a different tenant than the one currently "in session."
-- The app sets a session variable (app.current_tenant_id) right after
-- resolving who's logged in; every query in that request is then
-- automatically filtered by Postgres itself.

ALTER TABLE tenants                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_source_connections  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                ENABLE ROW LEVEL SECURITY;

-- The tenants table filters on its own id (a tenant "sees" only itself),
-- rather than a tenant_id foreign key like the other tables.
CREATE POLICY tenant_isolation_tenants ON tenants
    USING (id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_users ON users
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_roles ON roles
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_dsc ON data_source_connections
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY tenant_isolation_audit ON audit_log
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- Note: `permissions` is intentionally NOT restricted this way — it's a
-- shared, non-tenant-specific catalog every tenant reads from.
--
-- IMPORTANT CAVEAT: by default, a table owner/superuser bypasses Row-Level
-- Security entirely. These policies only take effect once the app connects
-- as a dedicated, non-superuser database role — see create_app_role.sql,
-- which must be run after this file.

-- ============================================================================
-- IDENTITY RESOLUTION FUNCTIONS
-- ============================================================================
-- Finding out "which tenant does this login belong to" is inherently a
-- cross-tenant lookup — it has to happen BEFORE we know which tenant to
-- restrict to. (A real Entra ID login has exactly the same problem: you
-- have to look up which tenant a signed-in email belongs to.) Rather than
-- letting the app's normal database role bypass Row-Level Security
-- everywhere just to solve this one problem, we give it access to two
-- narrow, purpose-built functions instead. SECURITY DEFINER means these
-- functions run with the privilege of whoever CREATED them (the database
-- owner, running this script) — not with the caller's more limited
-- privilege — but only for exactly the query written inside them.
-- Everything else the app does remains fully RLS-restricted.

CREATE FUNCTION list_demo_users_for_login()
RETURNS TABLE (id UUID, display_name TEXT, email TEXT, tenant_name TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id, u.display_name, u.email, t.name AS tenant_name
    FROM users u
    JOIN tenants t ON t.id = u.tenant_id
    WHERE u.is_active AND t.is_active
    ORDER BY t.name, u.display_name;
$$;

CREATE FUNCTION resolve_login_by_user_id(p_user_id UUID)
RETURNS TABLE (id UUID, tenant_id UUID, is_active BOOLEAN)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id, u.tenant_id, u.is_active
    FROM users u
    WHERE u.id = p_user_id;
$$;

-- No one gets to call these by default — access is granted explicitly and
-- only to the app's own role, in create_app_role.sql.
REVOKE ALL ON FUNCTION list_demo_users_for_login() FROM PUBLIC;
REVOKE ALL ON FUNCTION resolve_login_by_user_id(UUID) FROM PUBLIC;
