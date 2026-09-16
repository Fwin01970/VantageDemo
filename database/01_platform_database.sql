-- ============================================================================
-- RYZE INFINITY — PLATFORM DATABASE
-- ============================================================================
-- Run this ONCE, against a database you create just for this purpose
-- (e.g. a database literally named "ryze_platform"). This database's
-- ONLY job is:
--   1. Knowing which tenant databases exist and how to find each one.
--   2. A tiny "phone book" so login knows which tenant's database to
--      open for a given email — NOT the actual user account, NOT a
--      password, just enough to route the login attempt correctly.
--   3. Holding Super Admin accounts, which don't belong to any tenant
--      at all.
--
-- Nothing about any tenant's actual business data (users' full details,
-- use cases, credentials, dashboards, anything) lives in this database.
-- Every one of those lives ONLY inside that tenant's own separate
-- database (see 02_tenant_database_template.sql).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Tenants — the list of companies, and where each one's data lives ─────
CREATE TABLE tenants (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,              -- e.g. 'Vantage Insurance'
    industry    TEXT NOT NULL,
    db_name     TEXT NOT NULL UNIQUE,        -- e.g. 'tenant_vantage_insurance' —
                                               -- the actual Postgres database
                                               -- name this tenant's data lives in
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── The "phone book" — email → which tenant, nothing else ────────────────
-- This is intentionally the ONLY place a user's email appears outside
-- their own tenant's database. No password, no display name here — just
-- enough to answer "when someone types this email into the login box,
-- which tenant database do I need to open to check their password?"
-- Kept perfectly in sync with each tenant database's own `users` table
-- by the backend (every time a user is created/deleted in a tenant
-- database, the matching row here is created/deleted too).
CREATE TABLE user_directory (
    email       TEXT PRIMARY KEY,
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL             -- matches that user's id INSIDE their tenant's own database
);

CREATE INDEX idx_user_directory_tenant ON user_directory(tenant_id);

-- ── Super Admin accounts — belong to no tenant at all ─────────────────────
CREATE TABLE platform_admins (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email                 TEXT NOT NULL UNIQUE,
    display_name          TEXT NOT NULL,
    password_hash         TEXT,             -- NULL until they set a password
    is_active             BOOLEAN NOT NULL DEFAULT true,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until           TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at         TIMESTAMPTZ
);

-- ── Cross-tenant audit summary (optional, small) ──────────────────────────
-- Each tenant keeps its OWN full audit_log inside its own database (see
-- the tenant template). This table is just a lightweight pointer/index
-- so the Super Admin's Audit Log page can quickly filter "which tenant,
-- which user" without having to open and search every single tenant
-- database on every page load. The backend writes one small row here
-- every time it writes a full entry into a tenant's own audit_log.
CREATE TABLE platform_audit_index (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID,                       -- matches a user id inside that tenant's own database
    action      TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_platform_audit_tenant ON platform_audit_index(tenant_id);
CREATE INDEX idx_platform_audit_user ON platform_audit_index(user_id);
CREATE INDEX idx_platform_audit_time ON platform_audit_index(created_at DESC);

-- ============================================================================
-- Optional: create your first Super Admin login right now.
-- Replace the email/name below with the real ones you want to use, then
-- set a real password through the app afterward (this just creates the
-- account shell — password_hash starts empty until you set one).
-- ============================================================================
-- INSERT INTO platform_admins (email, display_name) VALUES
--     ('you@yourcompany.com', 'Your Name');
