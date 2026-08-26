-- ============================================================================
-- Real authentication: password login + OAuth (config-driven)
-- ============================================================================
-- auth_provider stays 'local' for email/password accounts, and becomes
-- 'microsoft' | 'google' | 'github' | 'facebook' for OAuth accounts. When
-- real Microsoft Entra ID credentials are available, the 'microsoft' path
-- here starts working with ZERO code changes — only .env values change
-- (see backend/.env.example).
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider TEXT NOT NULL DEFAULT 'local';
ALTER TABLE users ADD COLUMN IF NOT EXISTS oauth_subject TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_auth_provider_check;
ALTER TABLE users ADD CONSTRAINT users_auth_provider_check
    CHECK (auth_provider IN ('local', 'microsoft', 'google', 'github', 'facebook'));

-- One (provider, external id) pair maps to at most one account.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_oauth_identity
    ON users (auth_provider, oauth_subject)
    WHERE oauth_subject IS NOT NULL;

-- ============================================================================
-- SECURITY DEFINER functions for the pre-authentication lookups
-- ============================================================================
-- Every one of these runs BEFORE we know which tenant the caller belongs
-- to — that's the whole point of logging in — so a normal RLS-scoped
-- query can't work (RLS filters by current_tenant_id_safe(), which isn't
-- set yet). Same narrow, deliberate RLS-bypass pattern already used for
-- create_company_for_admin(), scoped to exactly what login needs.
-- ============================================================================

CREATE OR REPLACE FUNCTION find_user_for_login(p_email TEXT)
RETURNS TABLE (
    id UUID, tenant_id UUID, display_name TEXT, password_hash TEXT,
    auth_provider TEXT, failed_login_attempts INT, locked_until TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT id, tenant_id, display_name, password_hash, auth_provider,
           failed_login_attempts, locked_until
    FROM users WHERE lower(email) = lower(p_email);
$$;

CREATE OR REPLACE FUNCTION find_user_by_oauth(p_provider TEXT, p_subject TEXT)
RETURNS TABLE (id UUID, tenant_id UUID, display_name TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT id, tenant_id, display_name FROM users
    WHERE auth_provider = p_provider AND oauth_subject = p_subject;
$$;

CREATE OR REPLACE FUNCTION find_user_by_email_any_tenant(p_email TEXT)
RETURNS TABLE (id UUID, tenant_id UUID, display_name TEXT, auth_provider TEXT)
LANGUAGE sql SECURITY DEFINER AS $$
    SELECT id, tenant_id, display_name, auth_provider FROM users
    WHERE lower(email) = lower(p_email);
$$;

CREATE OR REPLACE FUNCTION link_oauth_identity(p_user_id UUID, p_provider TEXT, p_subject TEXT)
RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE users SET auth_provider = p_provider, oauth_subject = p_subject WHERE id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION record_login_success(p_user_id UUID)
RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$
    UPDATE users SET failed_login_attempts = 0, locked_until = NULL, last_login_at = now()
    WHERE id = p_user_id;
$$;

-- Threshold/lock-minutes are passed in from config.py rather than
-- hardcoded here, so ACCOUNT_LOCK_THRESHOLD/ACCOUNT_LOCK_MINUTES stay
-- the single source of truth.
CREATE OR REPLACE FUNCTION record_login_failure(p_user_id UUID, p_threshold INT, p_lock_minutes INT)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_attempts INT;
BEGIN
    UPDATE users SET failed_login_attempts = failed_login_attempts + 1
    WHERE id = p_user_id
    RETURNING failed_login_attempts INTO v_attempts;

    IF v_attempts >= p_threshold THEN
        UPDATE users SET locked_until = now() + make_interval(mins => p_lock_minutes)
        WHERE id = p_user_id;
    END IF;

    RETURN v_attempts;
END;
$$;
