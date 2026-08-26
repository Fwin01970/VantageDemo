-- ============================================================================
-- Ryze Infinity — generate a fake banking Gold-layer dataset from scratch
-- ============================================================================
-- Run this in the Databricks SQL Editor (or a notebook cell with %sql) —
-- paste the whole thing and run top to bottom, or run it statement by
-- statement if you want to watch each table get created.
--
-- Change CATALOG_NAME / SCHEMA_NAME below if you didn't use
-- "ryze_demo" / "gold" when you created them.
-- ============================================================================

USE CATALOG deplearning;
USE SCHEMA Gold;

-- ── Dimensions ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE dim_branch AS
SELECT * FROM VALUES
  (1,'Downtown Chicago','Midwest','IL'),
  (2,'Columbus Main','Midwest','OH'),
  (3,'Minneapolis North','Midwest','MN'),
  (4,'Manhattan Financial','Northeast','NY'),
  (5,'Boston Back Bay','Northeast','MA'),
  (6,'Philadelphia Center','Northeast','PA'),
  (7,'Atlanta Midtown','South','GA'),
  (8,'Dallas Uptown','South','TX'),
  (9,'Miami Brickell','South','FL'),
  (10,'San Francisco Bay','West','CA'),
  (11,'Seattle Downtown','West','WA'),
  (12,'Denver Central','West','CO')
AS t(branch_id, branch_name, region, state);

CREATE OR REPLACE TABLE dim_product AS
SELECT * FROM VALUES
  (1,'Auto Loan','Consumer Lending'),
  (2,'Personal Loan','Consumer Lending'),
  (3,'Credit Card','Consumer Lending'),
  (4,'Mortgage','Real Estate Lending'),
  (5,'HELOC','Real Estate Lending'),
  (6,'Business Loan','Commercial Lending')
AS t(product_id, product_name, product_category);

CREATE OR REPLACE TABLE dim_segment AS
SELECT * FROM VALUES
  (1,'Retail'), (2,'Small Business'), (3,'Commercial'), (4,'Private Banking')
AS t(segment_id, segment_name);

-- ── fact_loans — ~6,000 synthetic loans, 2023–2026 ───────────────────────
CREATE OR REPLACE TABLE fact_loans AS
WITH base AS (
  SELECT
    id + 1 AS loan_id,
    CAST(1 + floor(rand() * 6) AS INT) AS product_id,
    CAST(1 + floor(rand() * 12) AS INT) AS branch_id,
    element_at(array(1,1,1,2,2,3,4), CAST(1 + floor(rand() * 7) AS INT)) AS segment_id,
    date_add(DATE'2023-01-01', CAST(floor(rand() * 1095) AS INT)) AS origination_date,
    (500 + floor(rand() * 400)) * 100 AS base_amount,
    rand() AS dpd_roll,
    rand() AS rate_roll,
    rand() AS term_roll
  FROM range(6000) AS r(id)
),
priced AS (
  SELECT
    b.*,
    p.product_name,
    CASE p.product_name
      WHEN 'Mortgage'      THEN b.base_amount * 60
      WHEN 'HELOC'         THEN b.base_amount * 15
      WHEN 'Business Loan' THEN b.base_amount * 25
      WHEN 'Auto Loan'     THEN b.base_amount * 4
      WHEN 'Credit Card'   THEN b.base_amount * 0.3
      ELSE b.base_amount * 8
    END AS principal_amount,
    ROUND(CASE p.product_name
      WHEN 'Mortgage'      THEN 5.5 + b.rate_roll * 2
      WHEN 'HELOC'         THEN 7.0 + b.rate_roll * 2.5
      WHEN 'Business Loan' THEN 6.5 + b.rate_roll * 3
      WHEN 'Auto Loan'     THEN 4.5 + b.rate_roll * 4
      WHEN 'Credit Card'   THEN 16  + b.rate_roll * 8
      ELSE 8 + b.rate_roll * 6
    END, 2) AS interest_rate_pct,
    CASE p.product_name
      WHEN 'Mortgage'      THEN element_at(array(180,240,360), CAST(1 + floor(b.term_roll * 3) AS INT))
      WHEN 'HELOC'         THEN 120
      WHEN 'Business Loan' THEN element_at(array(36,60,84), CAST(1 + floor(b.term_roll * 3) AS INT))
      WHEN 'Auto Loan'     THEN element_at(array(36,48,60,72), CAST(1 + floor(b.term_roll * 4) AS INT))
      WHEN 'Credit Card'   THEN 0
      ELSE element_at(array(24,36,48), CAST(1 + floor(b.term_roll * 3) AS INT))
    END AS term_months,
    datediff(CURRENT_DATE(), b.origination_date) / 365.0 AS age_fraction,
    CASE
      WHEN b.dpd_roll < 0.82 THEN 0
      WHEN b.dpd_roll < 0.90 THEN 15 + CAST(floor(rand() * 15) AS INT)
      WHEN b.dpd_roll < 0.95 THEN 30 + CAST(floor(rand() * 30) AS INT)
      WHEN b.dpd_roll < 0.98 THEN 60 + CAST(floor(rand() * 30) AS INT)
      ELSE 90 + CAST(floor(rand() * 90) AS INT)
    END AS days_past_due,
    CASE
      WHEN b.dpd_roll < 0.82  THEN 'current'
      WHEN b.dpd_roll < 0.95  THEN 'delinquent'
      WHEN b.dpd_roll < 0.985 THEN 'default'
      ELSE 'charged_off'
    END AS status,
    CASE
      WHEN b.dpd_roll < 0.55 THEN 'A'
      WHEN b.dpd_roll < 0.80 THEN 'B'
      WHEN b.dpd_roll < 0.92 THEN 'C'
      WHEN b.dpd_roll < 0.98 THEN 'D'
      ELSE 'E'
    END AS risk_grade
  FROM base b
  JOIN dim_product p ON p.product_id = b.product_id
)
SELECT
  loan_id, product_id, branch_id, segment_id, origination_date,
  CAST(principal_amount AS DECIMAL(14,2)) AS principal_amount,
  interest_rate_pct,
  term_months,
  CAST(GREATEST(principal_amount * (1 - LEAST(age_fraction, 1) * 0.7), principal_amount * 0.05) AS DECIMAL(14,2)) AS outstanding_balance,
  days_past_due,
  CASE WHEN status = 'current' AND age_fraction > 2.5 AND rand() < 0.35 THEN 'paid_off' ELSE status END AS status,
  risk_grade
FROM priced;

-- ── fact_deposits — ~4,000 synthetic accounts ────────────────────────────
CREATE OR REPLACE TABLE fact_deposits AS
SELECT
  id + 1 AS account_id,
  CAST(1 + floor(rand() * 12) AS INT) AS branch_id,
  element_at(array(1,1,1,2,2,3,4), CAST(1 + floor(rand() * 7) AS INT)) AS segment_id,
  element_at(array('Checking','Checking','Savings','Savings','Money Market','CD'), CAST(1 + floor(rand() * 6) AS INT)) AS account_type,
  CAST(200 + rand() * rand() * 250000 AS DECIMAL(14,2)) AS balance,
  date_add(DATE'2022-01-01', CAST(floor(rand() * 1460) AS INT)) AS opened_date
FROM range(4000) AS r(id);

-- ── Gold views — what your AI assistant will actually query ──────────────
-- NOTE: Spark SQL doesn't support COUNT(*) FILTER (WHERE ...) — used
-- SUM(CASE WHEN ... THEN 1 ELSE 0 END) instead, the Spark SQL equivalent.
CREATE OR REPLACE VIEW vw_loan_portfolio_summary AS
SELECT
  p.product_name,
  p.product_category,
  b.region,
  year(l.origination_date) AS year_num,
  quarter(l.origination_date) AS quarter_num,
  COUNT(*) AS loan_count,
  SUM(l.principal_amount) AS total_principal,
  SUM(l.outstanding_balance) AS total_outstanding_balance,
  ROUND(AVG(l.interest_rate_pct), 2) AS avg_interest_rate_pct,
  SUM(CASE WHEN l.days_past_due >= 30 THEN 1 ELSE 0 END) AS delinquent_loan_count,
  ROUND(100.0 * SUM(CASE WHEN l.days_past_due >= 30 THEN 1 ELSE 0 END) / COUNT(*), 2) AS delinquency_rate_pct,
  SUM(CASE WHEN l.status IN ('default','charged_off') THEN 1 ELSE 0 END) AS nonperforming_loan_count,
  ROUND(100.0 * SUM(CASE WHEN l.status IN ('default','charged_off') THEN 1 ELSE 0 END) / COUNT(*), 2) AS npl_ratio_pct,
  SUM(CASE WHEN l.status = 'charged_off' THEN l.outstanding_balance ELSE 0 END) AS charged_off_balance
FROM fact_loans l
JOIN dim_product p ON p.product_id = l.product_id
JOIN dim_branch b ON b.branch_id = l.branch_id
GROUP BY p.product_name, p.product_category, b.region, year(l.origination_date), quarter(l.origination_date);

CREATE OR REPLACE VIEW vw_branch_performance AS
SELECT
  b.branch_name, b.region, b.state,
  year(d.opened_date) AS year_num,
  quarter(d.opened_date) AS quarter_num,
  COUNT(*) AS new_accounts,
  SUM(d.balance) AS total_deposit_balance,
  ROUND(AVG(d.balance), 2) AS avg_account_balance
FROM fact_deposits d
JOIN dim_branch b ON b.branch_id = d.branch_id
GROUP BY b.branch_name, b.region, b.state, year(d.opened_date), quarter(d.opened_date);

CREATE OR REPLACE VIEW vw_delinquency_trend AS
SELECT
  p.product_name,
  year(l.origination_date) AS year_num,
  quarter(l.origination_date) AS quarter_num,
  CASE
    WHEN l.days_past_due = 0 THEN 'Current'
    WHEN l.days_past_due < 30 THEN '1-29 DPD'
    WHEN l.days_past_due < 60 THEN '30-59 DPD'
    WHEN l.days_past_due < 90 THEN '60-89 DPD'
    ELSE '90+ DPD'
  END AS dpd_bucket,
  COUNT(*) AS loan_count,
  SUM(l.outstanding_balance) AS total_balance
FROM fact_loans l
JOIN dim_product p ON p.product_id = l.product_id
GROUP BY p.product_name, year(l.origination_date), quarter(l.origination_date),
  CASE
    WHEN l.days_past_due = 0 THEN 'Current'
    WHEN l.days_past_due < 30 THEN '1-29 DPD'
    WHEN l.days_past_due < 60 THEN '30-59 DPD'
    WHEN l.days_past_due < 90 THEN '60-89 DPD'
    ELSE '90+ DPD'
  END;

-- ── Documentation (the "business glossary" your AI reads) ────────────────
COMMENT ON TABLE vw_loan_portfolio_summary IS
  'Canonical loan portfolio view - one row per product/region/quarter. Use this for any delinquency, NPL, or portfolio-risk question. npl_ratio_pct is the standard non-performing-loan ratio (default+charged_off / total).';
COMMENT ON TABLE vw_branch_performance IS
  'Deposit-side branch performance - new accounts and deposit balances by branch/quarter. Use for branch or region deposit-growth questions, not lending questions.';
COMMENT ON TABLE vw_delinquency_trend IS
  'Loan aging buckets (DPD = days past due) by product/quarter. Use for delinquency-bucket breakdowns specifically; use vw_loan_portfolio_summary for one overall delinquency rate instead.';

-- ── Quick sanity check — run this after everything above finishes ────────
SELECT 'fact_loans' AS table_name, COUNT(*) AS row_count FROM fact_loans
UNION ALL
SELECT 'fact_deposits', COUNT(*) FROM fact_deposits
UNION ALL
SELECT 'vw_loan_portfolio_summary', COUNT(*) FROM vw_loan_portfolio_summary
UNION ALL
SELECT 'vw_branch_performance', COUNT(*) FROM vw_branch_performance
UNION ALL
SELECT 'vw_delinquency_trend', COUNT(*) FROM vw_delinquency_trend;
