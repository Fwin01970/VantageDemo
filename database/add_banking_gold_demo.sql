-- ============================================================================
-- Banking demo Gold layer (local, no Databricks connection required)
-- ============================================================================
-- We don't currently have real Databricks access for EITHER demo tenant,
-- which means Ask AI/Genie have nothing to actually query — everything
-- degrades to general-knowledge answers with no real numbers. This
-- creates a self-contained fake Gold layer, in our own Postgres, that
-- the backend can query exactly like it would query Databricks — same
-- SQL-in, {columns, rows}-out shape (see services/local_gold_client.py) —
-- so XYZ Bank's demo actually returns real, consistent numbers without
-- needing a real warehouse. When real Databricks access exists for a
-- tenant, flipping their data_source_connections row back to the
-- 'databricks' platform is the entire migration — no other code changes.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS gold_demo;

-- ── Dimensions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gold_demo.dim_branch (
    branch_id   SERIAL PRIMARY KEY,
    branch_name TEXT NOT NULL,
    region      TEXT NOT NULL,
    state       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gold_demo.dim_product (
    product_id       SERIAL PRIMARY KEY,
    product_name     TEXT NOT NULL,
    product_category TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gold_demo.dim_segment (
    segment_id   SERIAL PRIMARY KEY,
    segment_name TEXT NOT NULL
);

TRUNCATE gold_demo.dim_branch, gold_demo.dim_product, gold_demo.dim_segment RESTART IDENTITY CASCADE;

INSERT INTO gold_demo.dim_branch (branch_name, region, state) VALUES
    ('Downtown Chicago',   'Midwest',   'IL'),
    ('Columbus Main',      'Midwest',   'OH'),
    ('Minneapolis North',  'Midwest',   'MN'),
    ('Manhattan Financial','Northeast', 'NY'),
    ('Boston Back Bay',    'Northeast', 'MA'),
    ('Philadelphia Center','Northeast', 'PA'),
    ('Atlanta Midtown',    'South',     'GA'),
    ('Dallas Uptown',      'South',     'TX'),
    ('Miami Brickell',     'South',     'FL'),
    ('San Francisco Bay',  'West',      'CA'),
    ('Seattle Downtown',   'West',      'WA'),
    ('Denver Central',     'West',      'CO');

INSERT INTO gold_demo.dim_product (product_name, product_category) VALUES
    ('Auto Loan',      'Consumer Lending'),
    ('Personal Loan',  'Consumer Lending'),
    ('Credit Card',    'Consumer Lending'),
    ('Mortgage',       'Real Estate Lending'),
    ('HELOC',          'Real Estate Lending'),
    ('Business Loan',  'Commercial Lending');

INSERT INTO gold_demo.dim_segment (segment_name) VALUES
    ('Retail'), ('Small Business'), ('Commercial'), ('Private Banking');

-- ── Facts ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gold_demo.fact_loans (
    loan_id            SERIAL PRIMARY KEY,
    product_id         INT NOT NULL REFERENCES gold_demo.dim_product(product_id),
    branch_id          INT NOT NULL REFERENCES gold_demo.dim_branch(branch_id),
    segment_id         INT NOT NULL REFERENCES gold_demo.dim_segment(segment_id),
    origination_date   DATE NOT NULL,
    principal_amount   NUMERIC(14,2) NOT NULL,
    interest_rate_pct  NUMERIC(5,2) NOT NULL,
    term_months        INT NOT NULL,
    outstanding_balance NUMERIC(14,2) NOT NULL,
    days_past_due      INT NOT NULL DEFAULT 0,
    status             TEXT NOT NULL,   -- current | delinquent | default | charged_off | paid_off
    risk_grade         TEXT NOT NULL    -- A | B | C | D | E
);

CREATE TABLE IF NOT EXISTS gold_demo.fact_deposits (
    account_id     SERIAL PRIMARY KEY,
    branch_id      INT NOT NULL REFERENCES gold_demo.dim_branch(branch_id),
    segment_id     INT NOT NULL REFERENCES gold_demo.dim_segment(segment_id),
    account_type   TEXT NOT NULL,   -- Checking | Savings | CD | Money Market
    balance        NUMERIC(14,2) NOT NULL,
    opened_date    DATE NOT NULL
);

TRUNCATE gold_demo.fact_loans, gold_demo.fact_deposits RESTART IDENTITY CASCADE;

-- Reproducible "random" data — same numbers every time this migration
-- runs, so a demo doesn't quietly change between sessions.
SELECT setseed(0.42);

-- ~6,000 loans spread across 2023–2026, weighted toward Auto/Personal/
-- Credit Card (typical real-world product mix), with realistic-ish
-- interest rates by product category and a delinquency curve where most
-- loans are current and a smaller tail is past due or charged off.
INSERT INTO gold_demo.fact_loans (
    product_id, branch_id, segment_id, origination_date, principal_amount,
    interest_rate_pct, term_months, outstanding_balance, days_past_due, status, risk_grade
)
SELECT
    p.product_id,
    b.branch_id,
    s.segment_id,
    origination_date,
    principal_amount,
    interest_rate_pct,
    term_months,
    -- Outstanding balance amortizes down from principal based on how
    -- long ago the loan originated, with a floor so nothing goes
    -- negative — a rough but plausible approximation of paydown.
    GREATEST(principal_amount * (1 - LEAST(age_fraction, 1) * 0.7), principal_amount * 0.05)::NUMERIC(14,2) AS outstanding_balance,
    days_past_due,
    status,
    risk_grade
FROM (
    SELECT
        n,
        (ARRAY[1,1,1,2,2,2,3,3,3,3,4,4,5,6])[1 + floor(random()*14)::int] AS product_idx,
        1 + floor(random()*12)::int AS branch_idx,
        (ARRAY[1,1,1,2,2,3,4])[1 + floor(random()*7)::int] AS segment_idx,
        (DATE '2023-01-01' + (floor(random()*1095))::int) AS origination_date,
        round((500 + random()*4)::numeric, 0) * 100 AS base_amount,
        random() AS dpd_roll
    FROM generate_series(1, 6000) AS n
) g
JOIN gold_demo.dim_product p ON p.product_id = g.product_idx
JOIN gold_demo.dim_branch  b ON b.branch_id = g.branch_idx
JOIN gold_demo.dim_segment s ON s.segment_id = g.segment_idx
CROSS JOIN LATERAL (
    SELECT
        CASE p.product_name
            WHEN 'Mortgage'      THEN base_amount * 60
            WHEN 'HELOC'         THEN base_amount * 15
            WHEN 'Business Loan' THEN base_amount * 25
            WHEN 'Auto Loan'     THEN base_amount * 4
            WHEN 'Credit Card'   THEN base_amount * 0.3
            ELSE base_amount * 8  -- Personal Loan
        END AS principal_amount,
        CASE p.product_name
            WHEN 'Mortgage'      THEN round((5.5 + random()*2)::numeric, 2)
            WHEN 'HELOC'         THEN round((7.0 + random()*2.5)::numeric, 2)
            WHEN 'Business Loan' THEN round((6.5 + random()*3)::numeric, 2)
            WHEN 'Auto Loan'     THEN round((4.5 + random()*4)::numeric, 2)
            WHEN 'Credit Card'   THEN round((16 + random()*8)::numeric, 2)
            ELSE round((8 + random()*6)::numeric, 2)  -- Personal Loan
        END AS interest_rate_pct,
        CASE p.product_name
            WHEN 'Mortgage'      THEN (ARRAY[180,240,360])[1+floor(random()*3)::int]
            WHEN 'HELOC'         THEN 120
            WHEN 'Business Loan' THEN (ARRAY[36,60,84])[1+floor(random()*3)::int]
            WHEN 'Auto Loan'     THEN (ARRAY[36,48,60,72])[1+floor(random()*4)::int]
            WHEN 'Credit Card'   THEN 0
            ELSE (ARRAY[24,36,48])[1+floor(random()*3)::int]  -- Personal Loan
        END AS term_months,
        (CURRENT_DATE - origination_date) / 365.0 AS age_fraction,
        CASE
            WHEN dpd_roll < 0.82 THEN 0
            WHEN dpd_roll < 0.90 THEN 15 + floor(random()*15)::int
            WHEN dpd_roll < 0.95 THEN 30 + floor(random()*30)::int
            WHEN dpd_roll < 0.98 THEN 60 + floor(random()*30)::int
            ELSE 90 + floor(random()*90)::int
        END AS days_past_due,
        CASE
            WHEN dpd_roll < 0.82 THEN 'current'
            WHEN dpd_roll < 0.95 THEN 'delinquent'
            WHEN dpd_roll < 0.985 THEN 'default'
            ELSE 'charged_off'
        END AS status,
        CASE
            WHEN dpd_roll < 0.55 THEN 'A'
            WHEN dpd_roll < 0.80 THEN 'B'
            WHEN dpd_roll < 0.92 THEN 'C'
            WHEN dpd_roll < 0.98 THEN 'D'
            ELSE 'E'
        END AS risk_grade
) calc;

-- A modest number of loans marked paid_off, to keep the status mix
-- realistic (a portfolio isn't just "current" vs "in trouble").
UPDATE gold_demo.fact_loans SET status = 'paid_off', days_past_due = 0
WHERE status = 'current' AND origination_date < CURRENT_DATE - INTERVAL '2.5 years' AND random() < 0.35;

-- ~4,000 deposit accounts.
INSERT INTO gold_demo.fact_deposits (branch_id, segment_id, account_type, balance, opened_date)
SELECT
    1 + floor(random()*12)::int,
    (ARRAY[1,1,1,2,2,3,4])[1 + floor(random()*7)::int],
    (ARRAY['Checking','Checking','Savings','Savings','Money Market','CD'])[1 + floor(random()*6)::int],
    round((200 + random()*random()*250000)::numeric, 2),
    DATE '2022-01-01' + (floor(random()*1460))::int
FROM generate_series(1, 4000);

-- ── Gold views — what the LLM actually queries ──────────────────────────
CREATE OR REPLACE VIEW gold_demo.vw_loan_portfolio_summary AS
SELECT
    p.product_name,
    p.product_category,
    b.region,
    EXTRACT(YEAR FROM l.origination_date)::INT AS year_num,
    EXTRACT(QUARTER FROM l.origination_date)::INT AS quarter_num,
    COUNT(*) AS loan_count,
    SUM(l.principal_amount) AS total_principal,
    SUM(l.outstanding_balance) AS total_outstanding_balance,
    ROUND(AVG(l.interest_rate_pct), 2) AS avg_interest_rate_pct,
    COUNT(*) FILTER (WHERE l.days_past_due >= 30) AS delinquent_loan_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE l.days_past_due >= 30) / NULLIF(COUNT(*), 0), 2) AS delinquency_rate_pct,
    COUNT(*) FILTER (WHERE l.status IN ('default', 'charged_off')) AS nonperforming_loan_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE l.status IN ('default', 'charged_off')) / NULLIF(COUNT(*), 0), 2) AS npl_ratio_pct,
    SUM(l.outstanding_balance) FILTER (WHERE l.status = 'charged_off') AS charged_off_balance
FROM gold_demo.fact_loans l
JOIN gold_demo.dim_product p ON p.product_id = l.product_id
JOIN gold_demo.dim_branch b ON b.branch_id = l.branch_id
GROUP BY p.product_name, p.product_category, b.region,
         EXTRACT(YEAR FROM l.origination_date), EXTRACT(QUARTER FROM l.origination_date);

CREATE OR REPLACE VIEW gold_demo.vw_branch_performance AS
SELECT
    b.branch_name,
    b.region,
    b.state,
    EXTRACT(YEAR FROM d.opened_date)::INT AS year_num,
    EXTRACT(QUARTER FROM d.opened_date)::INT AS quarter_num,
    COUNT(*) AS new_accounts,
    SUM(d.balance) AS total_deposit_balance,
    ROUND(AVG(d.balance), 2) AS avg_account_balance
FROM gold_demo.fact_deposits d
JOIN gold_demo.dim_branch b ON b.branch_id = d.branch_id
GROUP BY b.branch_name, b.region, b.state,
         EXTRACT(YEAR FROM d.opened_date), EXTRACT(QUARTER FROM d.opened_date);

CREATE OR REPLACE VIEW gold_demo.vw_delinquency_trend AS
SELECT
    p.product_name,
    EXTRACT(YEAR FROM l.origination_date)::INT AS year_num,
    EXTRACT(QUARTER FROM l.origination_date)::INT AS quarter_num,
    CASE
        WHEN l.days_past_due = 0 THEN 'Current'
        WHEN l.days_past_due < 30 THEN '1-29 DPD'
        WHEN l.days_past_due < 60 THEN '30-59 DPD'
        WHEN l.days_past_due < 90 THEN '60-89 DPD'
        ELSE '90+ DPD'
    END AS dpd_bucket,
    COUNT(*) AS loan_count,
    SUM(l.outstanding_balance) AS total_balance
FROM gold_demo.fact_loans l
JOIN gold_demo.dim_product p ON p.product_id = l.product_id
GROUP BY p.product_name, EXTRACT(YEAR FROM l.origination_date), EXTRACT(QUARTER FROM l.origination_date),
         CASE
             WHEN l.days_past_due = 0 THEN 'Current'
             WHEN l.days_past_due < 30 THEN '1-29 DPD'
             WHEN l.days_past_due < 60 THEN '30-59 DPD'
             WHEN l.days_past_due < 90 THEN '60-89 DPD'
             ELSE '90+ DPD'
         END;

-- ── Table/column documentation (LocalGoldClient's describe_* reads this,
--    same information_schema convention Databricks itself uses) ─────────
COMMENT ON VIEW gold_demo.vw_loan_portfolio_summary IS
    'Canonical loan portfolio view — one row per product/region/quarter. Use this for any loss ratio, delinquency, NPL, or portfolio-risk question. npl_ratio_pct is the standard non-performing-loan ratio (default+charged_off / total).';
COMMENT ON VIEW gold_demo.vw_branch_performance IS
    'Deposit-side branch performance — new accounts and deposit balances by branch/quarter. Use for branch/region deposit growth questions, not for lending questions.';
COMMENT ON VIEW gold_demo.vw_delinquency_trend IS
    'Loan aging buckets (DPD = days past due) by product/quarter. Use for delinquency-bucket breakdowns specifically; use vw_loan_portfolio_summary for a single overall delinquency rate instead.';

-- ── Grants — the app connects as ryze_app (see create_app_role.sql),
--    which needs read access to this schema like any other. ────────────
GRANT USAGE ON SCHEMA gold_demo TO ryze_app;
GRANT SELECT ON ALL TABLES IN SCHEMA gold_demo TO ryze_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold_demo GRANT SELECT ON TABLES TO ryze_app;

-- ── Point XYZ Bank at this local Gold layer instead of a real Databricks
--    connection — see services/local_gold_client.py + the
--    data_source_resolver.py branch on platform = 'local_demo'. ────────
UPDATE data_source_connections
SET platform = 'local_demo',
    config = '{"schema": "gold_demo", "description": "Local fake Gold-layer banking dataset for demo purposes — no real Databricks connection required."}',
    secret_ref = NULL,
    is_active = true
WHERE tenant_id = '22222222-2222-2222-2222-222222222222' AND platform = 'databricks';

-- In case that tenant somehow has no data_source_connections row at all
-- (shouldn't happen given seed.sql, but keeps this migration safe to run
-- standalone against a differently-seeded database too).
INSERT INTO data_source_connections (tenant_id, platform, config, secret_ref, is_active)
SELECT '22222222-2222-2222-2222-222222222222', 'local_demo',
       '{"schema": "gold_demo", "description": "Local fake Gold-layer banking dataset for demo purposes."}',
       NULL, true
WHERE NOT EXISTS (
    SELECT 1 FROM data_source_connections WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
);
