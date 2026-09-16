-- ============================================================================
-- Ryze Infinity — Demo Seed Data
-- ============================================================================
-- Creates two fake tenants (one Insurance, one Banking) with a couple of
-- users each, so we can prove multi-tenancy works BEFORE any real
-- Databricks or Entra ID connection exists.
--
-- This data is clearly fake/demo — nothing here should ever be mistaken
-- for a real client. Run this AFTER schema.sql.
--
-- SAFE TO RE-RUN: every INSERT below uses ON CONFLICT DO NOTHING, same
-- as every other migration file in this project — running this twice
-- (or running it against a database that already has this data from an
-- earlier session) just does nothing on the second pass instead of
-- crashing with a duplicate-key error.
-- ============================================================================

-- ── Permission catalog (shared across all tenants) ─────────────────────
-- Every user within a tenant gets the SAME role with the SAME
-- permissions below — there is no tenant-level "admin" tier anymore.
-- Only Platform Admin (see add_platform_admin.sql) manages
-- tenants/users/roles; a Team Member role's permissions are about what
-- product features are available, not who can manage whom.
INSERT INTO permissions (code, description) VALUES
    ('data:query',        'Ask natural-language questions against tenant data'),
    ('dashboard:manage',  'Create and edit dashboards'),
    ('tenant:manage',     'Create/edit use cases and business glossary annotations for this tenant'),
    ('audit:view',        'View this tenant''s own Governance panel (activity, guardrails, audit log)'),
    ('governance:manage', 'Approve/reject borderline (HITL) questions in this tenant''s Governance panel')
ON CONFLICT (code) DO NOTHING;

-- ── Tenant 1: ABC Insurance ──────────────────────────────────────────────
INSERT INTO tenants (id, name, industry) VALUES
    ('11111111-1111-1111-1111-111111111111', 'ABC Insurance (Demo)', 'insurance')
ON CONFLICT (id) DO NOTHING;

-- Exactly one role per tenant — every demo user of this tenant gets it,
-- with identical permissions. genie:access is added separately by
-- add_genie_permission.sql, granted to this same role.
INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('a1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
     'Team Member', 'Full access for this tenant — every user has the same permissions')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a1111111-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('data:query', 'dashboard:manage', 'tenant:manage', 'audit:view', 'governance:manage')
ON CONFLICT DO NOTHING;

-- Exactly 2 demo users, both on the SAME role — no viewer/admin split.
INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'sarah.chen@abcinsurance.demo', 'Sarah Chen'),
    ('b1111111-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'raj.mehta@abcinsurance.demo', 'Raj Mehta')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b1111111-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001'),
    ('b1111111-0000-0000-0000-000000000002', 'a1111111-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- ── Tenant 2: XYZ Bank ───────────────────────────────────────────────────
-- A second, completely separate tenant — used to prove that logging in as
-- an ABC Insurance user never shows XYZ Bank's data, and vice versa.
INSERT INTO tenants (id, name, industry) VALUES
    ('22222222-2222-2222-2222-222222222222', 'XYZ Bank (Demo)', 'banking')
ON CONFLICT (id) DO NOTHING;

INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('a2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
     'Team Member', 'Full access for this tenant — every user has the same permissions')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('data:query', 'dashboard:manage', 'tenant:manage', 'audit:view', 'governance:manage')
ON CONFLICT DO NOTHING;

-- Exactly 2 demo users, both on the SAME role.
INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'james.okafor@xyzbank.demo', 'James Okafor'),
    ('b2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'priya.patel@xyzbank.demo', 'Priya Patel')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b2222222-0000-0000-0000-000000000001', 'a2222222-0000-0000-0000-000000000001'),
    ('b2222222-0000-0000-0000-000000000002', 'a2222222-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- Note: no placeholder data_source_connections row here anymore — Query
-- Parameters now live in each tenant's own private schema (see
-- move_query_parameters_to_tenant_schema.sql) and are set up through the
-- Master Admin UI, either at tenant-creation time or afterward, not
-- seeded as inert placeholder data.
