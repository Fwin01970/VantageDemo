-- ============================================================================
-- XYZ Bank (Demo) — multiple analyst personas + banking use cases
-- ============================================================================
-- The insurance demo tenant only ever needed one real login (Sarah Chen)
-- since it's a single-persona walkthrough. Banking analytics genuinely
-- involves several different roles looking at the same data with
-- different questions in mind — this seeds that properly instead of
-- reusing James Okafor for everything.
-- ============================================================================

-- ── Roles ─────────────────────────────────────────────────────────────────
-- 'Risk Analyst' already exists from seed.sql (data:query, dashboard:manage)
-- — kept as-is for James Okafor. These are new, each with a permission
-- mix that matches what that role would realistically need day to day.
INSERT INTO roles (id, tenant_id, name, description) VALUES
    ('a2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Loan Portfolio Manager', 'Owns loan portfolio performance and reporting'),
    ('a2222222-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Branch Operations Director', 'Oversees branch-level deposit and account performance'),
    ('a2222222-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'Compliance & AML Officer', 'Monitors for regulatory and fraud risk; full audit visibility'),
    ('a2222222-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'Chief Financial Officer', 'Full analytical and administrative access')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000002', id FROM permissions
    WHERE code IN ('data:query', 'genie:access', 'dashboard:manage')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000003', id FROM permissions
    WHERE code IN ('data:query', 'dashboard:manage')
ON CONFLICT DO NOTHING;

-- Compliance needs to see everything that happened, not just query data.
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000004', id FROM permissions
    WHERE code IN ('data:query', 'genie:access', 'audit:view', 'governance:manage')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000005', id FROM permissions
    WHERE code IN ('data:query', 'genie:access', 'dashboard:manage', 'audit:view', 'tenant:manage')
ON CONFLICT DO NOTHING;

-- Give James Okafor's existing 'Risk Analyst' role Genie access too —
-- it only had data:query + dashboard:manage before.
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a2222222-0000-0000-0000-000000000001', id FROM permissions WHERE code = 'genie:access'
ON CONFLICT DO NOTHING;

-- ── Users ─────────────────────────────────────────────────────────────────
INSERT INTO users (id, tenant_id, email, display_name) VALUES
    ('b2222222-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'elena.marsh@xyzbank.demo',   'Elena Marsh'),
    ('b2222222-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'diane.osei@xyzbank.demo',    'Diane Osei'),
    ('b2222222-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'marcus.lindqvist@xyzbank.demo', 'Marcus Lindqvist'),
    ('b2222222-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'priya.subramanian@xyzbank.demo', 'Priya Subramanian')
ON CONFLICT DO NOTHING;

INSERT INTO user_roles (user_id, role_id) VALUES
    ('b2222222-0000-0000-0000-000000000002', 'a2222222-0000-0000-0000-000000000002'),
    ('b2222222-0000-0000-0000-000000000003', 'a2222222-0000-0000-0000-000000000003'),
    ('b2222222-0000-0000-0000-000000000004', 'a2222222-0000-0000-0000-000000000004'),
    ('b2222222-0000-0000-0000-000000000005', 'a2222222-0000-0000-0000-000000000005')
ON CONFLICT DO NOTHING;

-- ── Banking-flavored use cases ──────────────────────────────────────────
-- Replaces the generic ones with questions that actually resolve against
-- gold_demo's real views (see add_banking_gold_demo.sql) — every
-- sample_question here is a question that will genuinely run and return
-- real numbers, not just plausible-sounding filler.
DELETE FROM use_cases WHERE tenant_id = '22222222-2222-2222-2222-222222222222';

INSERT INTO use_cases (tenant_id, title, description, category, sample_question, icon_key) VALUES
    ('22222222-2222-2222-2222-222222222222', 'Loan portfolio risk',
     'Delinquency and non-performing loan trends across the portfolio.',
     'Risk', 'What is our current delinquency rate and NPL ratio by product line?', 'alert-triangle'),
    ('22222222-2222-2222-2222-222222222222', 'Delinquency aging',
     'How loans move through 30/60/90+ day past-due buckets over time.',
     'Risk', 'Show me the delinquency aging buckets by product for the last two quarters', 'trending-up'),
    ('22222222-2222-2222-2222-222222222222', 'Branch deposit performance',
     'New account growth and deposit balances by branch and region.',
     'Growth', 'Which branches had the strongest deposit growth this year?', 'building'),
    ('22222222-2222-2222-2222-222222222222', 'Portfolio yield',
     'Average interest rate and outstanding balance by product line.',
     'Profitability', 'What is our average interest rate and total outstanding balance by product?', 'percent'),
    ('22222222-2222-2222-2222-222222222222', 'Charge-off exposure',
     'Where charged-off balances are concentrated across the book.',
     'Risk', 'Which product lines and regions have the highest charged-off balances?', 'trending-down');
