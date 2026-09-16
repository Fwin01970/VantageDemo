-- ============================================================================
-- OPTIONAL demo users — run this on a tenant database if you want 2
-- sample logins to test with (not required — skip this file entirely
-- for a real customer's database).
-- ============================================================================
-- Passwords aren't set here — either set one through the app's normal
-- signup/reset flow, or use your temporary demo-login feature if your
-- app still has one.

INSERT INTO users (id, email, display_name) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'person.one@example.com', 'Person One'),
    ('a0000000-0000-0000-0000-000000000002', 'person.two@example.com', 'Person Two');

INSERT INTO user_roles (user_id, role_id) VALUES
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1'),
    ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1');
