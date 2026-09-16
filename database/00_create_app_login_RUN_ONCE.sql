-- ============================================================================
-- App connection login — run this ONCE ONLY, on any single database
-- ============================================================================
-- A Postgres "role" (login) is shared across your whole server, not
-- tied to one database — so unlike the other files in this folder,
-- this one is NOT meant to be run again for every tenant. Run it once,
-- right after your server is set up, before creating any databases.
--
-- Replace 'ChangeThisPassword' with a real password before running —
-- then use that SAME password in the backend's connection settings for
-- every database it connects to.
--
-- The backend should NEVER connect as the Postgres superuser — a
-- superuser automatically bypasses every privacy rule (Row-Level
-- Security) set up in 02_tenant_database_template.sql, which would
-- silently defeat the whole point of them existing.
-- ============================================================================

CREATE ROLE ryze_app WITH
    LOGIN
    PASSWORD 'Welcome#1996'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOBYPASSRLS;
