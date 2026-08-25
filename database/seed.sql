-- ============================================================================
-- Ryze Infinity — Demo Seed Data
-- ============================================================================
-- Creates two fake tenants (one Insurance, one Banking) with a couple of
-- users each, so we can prove multi-tenancy works BEFORE any real
-- Databricks or Entra ID connection exists.
--
-- This data is clearly fake/demo — nothing here should ever be mistaken
-- for a real client. Run this AFTER schema.sql.
-- ============================================================================

-- ── Permission catalog (shared across all tenants) ─────────────────────
INSERT INTO permissions (code, description) VALUES
    ('data:query',      'Ask natural-language questions against tenant data'),
    ('dashboard:manage','Create and edit dashboards'),
    ('tenant:manage',   'Manage tenant settings, users, and roles'),
    ('audit:view',      'View the audit log');

-- ── Tenant 1: ABC Insurance ──────────────────────────────────────────────
INSERT INTO tenants (id, name, industry) VALUES
    ('11111111-1111-1111-1111-111111111111', 'ABC Insurance (Demo)', 'insurance');

INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('a1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Claims Director', 'Full analytical access for this tenant'),
    ('a1111111-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Viewer', 'Read-only dashboard access');

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a1111111-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('data:query', 'dashboard:manage', 'tenant:manage', 'audit:view');
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a1111111-0000-0000-0000-000000000002', id FROM permissions
    WHERE code IN ('data:query');

INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'sarah.chen@abcinsurance.demo', 'Sarah Chen'),
    ('b1111111-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'viewer@abcinsurance.demo', 'Demo Viewer');

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b1111111-0000-0000-0000-000000000001', 'a1111111-0000-0000-0000-000000000001'),
    ('b1111111-0000-0000-0000-000000000002', 'a1111111-0000-0000-0000-000000000002');

-- ── Tenant 2: XYZ Bank ───────────────────────────────────────────────────
-- A second, completely separate tenant — used to prove that logging in as
-- an ABC Insurance user never shows XYZ Bank's data, and vice versa.
INSERT INTO tenants (id, name, industry) VALUES
    ('22222222-2222-2222-2222-222222222222', 'XYZ Bank (Demo)', 'banking');

INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('a2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Risk Analyst', 'Full analytical access for this tenant');

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000001', id FROM permissions
    WHERE code IN ('data:query', 'dashboard:manage');

INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b2222222-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'james.okafor@xyzbank.demo', 'James Okafor');

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b2222222-0000-0000-0000-000000000001', 'a2222222-0000-0000-0000-000000000001');

-- ── Placeholder data source connection (no real Databricks yet) ────────
INSERT INTO data_source_connections (tenant_id, platform, config, secret_ref, is_active) VALUES
    ('11111111-1111-1111-1111-111111111111', 'databricks', '{"host": null, "catalog": null, "schema": null}', NULL, false),
    ('22222222-2222-2222-2222-222222222222', 'databricks', '{"host": null, "catalog": null, "schema": null}', NULL, false);
