-- ============================================================================
-- Ryze Infinity — Create a dedicated app database role
-- ============================================================================
-- WHY THIS FILE EXISTS:
-- Postgres automatically SKIPS Row-Level Security checks for two kinds of
-- accounts: (1) superusers, and (2) the owner of the table. Up to now, the
-- app has been connecting as the "postgres" account, which is a superuser
-- — so even though the RLS policies in schema.sql are correct and active,
-- Postgres was quietly ignoring them for us. This file creates a normal,
-- restricted account with none of those special privileges, so RLS
-- actually takes effect once the app connects as this account instead.
--
-- Run this ONCE, after schema.sql and seed.sql, while still connected as
-- the postgres superuser (pgAdmin's default connection is fine for this).
-- ============================================================================

-- Replace 'ChooseAStrongPasswordHere' with a real password of your choosing
-- before running this — then use that same password in backend/.env.
CREATE ROLE ryze_app WITH
    LOGIN
    PASSWORD 'ChooseAStrongPasswordHere'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOBYPASSRLS;          -- explicit: this role must NOT skip RLS checks

-- Let this role connect to the database at all, and use its main schema.
GRANT CONNECT ON DATABASE ryze_infinity TO ryze_app;
GRANT USAGE ON SCHEMA public TO ryze_app;

-- Let it read/write rows in the existing tables (RLS policies still apply
-- on top of this — this grant controls "can touch the table at all",
-- RLS controls "which rows, specifically").
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ryze_app;

-- Make sure any tables we add LATER automatically grant this role the same
-- access, without having to remember to re-run a GRANT every time.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ryze_app;

-- Note for later phases: the RLS policies in schema.sql only have a USING
-- clause, which governs SELECT/UPDATE/DELETE visibility. Once the app
-- starts INSERTing tenant-scoped rows itself (e.g. audit log entries),
-- those policies will also need a WITH CHECK clause so Postgres validates
-- new rows match the current tenant too, not just filters existing ones.
-- Not needed yet since every Phase 1 endpoint is read-only.

-- Let the app role call the two identity-resolution functions defined at
-- the bottom of schema.sql (needed because login has to look up "which
-- tenant is this user in" BEFORE we know which tenant to restrict to —
-- see the comment above those functions for why that can't go through
-- the normal RLS-protected path).
GRANT EXECUTE ON FUNCTION list_demo_users_for_login() TO ryze_app;
GRANT EXECUTE ON FUNCTION resolve_login_by_user_id(UUID) TO ryze_app;

