-- ============================================================================
-- Ryze Infinity — generate a fake Insurance Gold-layer dataset from scratch
-- ============================================================================
-- Run this in the Databricks SQL Editor (or a notebook cell with %sql) —
-- paste the whole thing and run top to bottom, or run it statement by
-- statement if you want to watch each table get created.
--
-- Change CATALOG_NAME / SCHEMA_NAME below to whatever catalog/schema you
-- want this in. Whatever you pick here, use the EXACT same catalog and
-- schema when you set this tenant's Query Parameters in Master Admin →
-- Tenants → Manage → Query Parameters — the app reads from wherever you
-- point it, so the two have to match.
-- ============================================================================

USE CATALOG ryze_demo;
-- Creates the schema if it doesn't exist yet, so this script doesn't
-- assume anyone already set it up by hand. (The CATALOG itself is
-- assumed to already exist — creating a new catalog typically needs
-- metastore-admin rights beyond a standard workspace user's access.)
CREATE SCHEMA IF NOT EXISTS gold;
USE SCHEMA gold;

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
  (1,'Auto',       'Personal Lines'),
  (2,'Home',       'Personal Lines'),
  (3,'Renters',    'Personal Lines'),
  (4,'Life',       'Life & Health'),
  (5,'Umbrella',   'Personal Lines'),
  (6,'Commercial Property', 'Commercial Lines'),
  (7,'Workers Comp', 'Commercial Lines')
AS t(product_id, product_name, product_category);

CREATE OR REPLACE TABLE dim_segment AS
SELECT * FROM VALUES
  (1,'Personal'), (2,'Small Business'), (3,'Commercial'), (4,'High Net Worth')
AS t(segment_id, segment_name);

-- ── fact_policies — ~6,000 synthetic policies, 2023–2026 ─────────────────
CREATE OR REPLACE TABLE fact_policies AS
WITH base AS (
  SELECT
    id + 1 AS policy_id,
    CAST(1 + floor(rand() * 7) AS INT) AS product_id,
    CAST(1 + floor(rand() * 12) AS INT) AS branch_id,
    element_at(array(1,1,1,2,2,3,4), CAST(1 + floor(rand() * 7) AS INT)) AS segment_id,
    date_add(DATE'2023-01-01', CAST(floor(rand() * 1095) AS INT)) AS effective_date,
    rand() AS premium_roll,
    rand() AS risk_roll,
    rand() AS status_roll
  FROM range(6000) AS r(id)
),
priced AS (
  SELECT
    b.*,
    p.product_name,
    -- Annual premium varies a lot by line of business — commercial and
    -- home carry far higher premiums than renters or auto.
    ROUND(CASE p.product_name
      WHEN 'Auto'               THEN 800  + b.premium_roll * 1800
      WHEN 'Home'                THEN 1200 + b.premium_roll * 3500
      WHEN 'Renters'             THEN 150  + b.premium_roll * 350
      WHEN 'Life'                THEN 400  + b.premium_roll * 2600
      WHEN 'Umbrella'            THEN 250  + b.premium_roll * 750
      WHEN 'Commercial Property' THEN 3000 + b.premium_roll * 12000
      ELSE                            2000 + b.premium_roll * 9000  -- Workers Comp
    END, 2) AS premium_amount,
    CASE
      WHEN b.risk_roll < 0.55 THEN 'A'
      WHEN b.risk_roll < 0.80 THEN 'B'
      WHEN b.risk_roll < 0.93 THEN 'C'
      WHEN b.risk_roll < 0.98 THEN 'D'
      ELSE 'E'
    END AS risk_grade,
    CASE
      WHEN b.status_roll < 0.80 THEN 'active'
      WHEN b.status_roll < 0.90 THEN 'renewed'
      WHEN b.status_roll < 0.96 THEN 'lapsed'
      ELSE 'cancelled'
    END AS status
  FROM base b
  JOIN dim_product p ON p.product_id = b.product_id
)
SELECT
  policy_id, product_id, branch_id, segment_id, effective_date,
  CAST(premium_amount AS DECIMAL(14,2)) AS premium_amount,
  risk_grade,
  status
FROM priced;

-- ── fact_claims — ~2,300 synthetic claims against those policies ────────
-- Roughly a 38% claim-frequency rate overall, weighted so worse risk
-- grades and Home/Commercial lines see proportionally more claims —
-- realistic enough to produce a believable loss ratio spread across
-- product lines rather than a flat, uninteresting number everywhere.
CREATE OR REPLACE TABLE fact_claims AS
WITH claimable AS (
  SELECT
    p.policy_id, p.product_id, p.branch_id, p.segment_id, p.effective_date,
    p.premium_amount, p.risk_grade,
    rand() AS claim_roll,
    rand() AS sev_roll,
    rand() AS status_roll
  FROM fact_policies p
),
picked AS (
  SELECT *,
    CASE risk_grade WHEN 'A' THEN 0.20 WHEN 'B' THEN 0.32 WHEN 'C' THEN 0.45 WHEN 'D' THEN 0.60 ELSE 0.75 END
    * (CASE (SELECT product_name FROM dim_product WHERE product_id = claimable.product_id)
         WHEN 'Home' THEN 1.15 WHEN 'Commercial Property' THEN 1.25 WHEN 'Workers Comp' THEN 1.2 ELSE 1.0 END)
    AS claim_probability
  FROM claimable
)
SELECT
  monotonically_increasing_id() + 1 AS claim_id,
  policy_id, product_id, branch_id, segment_id,
  date_add(effective_date, CAST(floor(rand() * 330) AS INT)) AS claim_date,
  CAST(GREATEST(200, premium_amount * (0.3 + sev_roll * 2.2)) AS DECIMAL(14,2)) AS claim_amount_incurred,
  CAST(GREATEST(150, premium_amount * (0.3 + sev_roll * 2.2) * (CASE WHEN status_roll < 0.85 THEN 1.0 ELSE 0.9 * rand() END)) AS DECIMAL(14,2)) AS claim_amount_paid,
  CASE
    WHEN status_roll < 0.70 THEN 'closed'
    WHEN status_roll < 0.90 THEN 'open'
    ELSE 'denied'
  END AS claim_status
FROM picked
WHERE claim_roll < claim_probability;

-- ── Gold views — what your AI assistant will actually query ──────────────
-- NOTE: Spark SQL doesn't support COUNT(*) FILTER (WHERE ...) — used
-- SUM(CASE WHEN ... THEN 1 ELSE 0 END) instead, the Spark SQL equivalent.
CREATE OR REPLACE VIEW vw_loss_ratio_summary AS
SELECT
  p.product_name,
  p.product_category,
  b.region,
  year(pol.effective_date) AS year_num,
  quarter(pol.effective_date) AS quarter_num,
  COUNT(DISTINCT pol.policy_id) AS policy_count,
  SUM(pol.premium_amount) AS total_premium,
  COALESCE(SUM(c.claim_amount_paid), 0) AS total_claims_paid,
  ROUND(100.0 * COALESCE(SUM(c.claim_amount_paid), 0) / NULLIF(SUM(pol.premium_amount), 0), 2) AS loss_ratio_pct,
  COUNT(c.claim_id) AS claim_count,
  ROUND(100.0 * COUNT(c.claim_id) / NULLIF(COUNT(DISTINCT pol.policy_id), 0), 2) AS claim_frequency_pct
FROM fact_policies pol
JOIN dim_product p ON p.product_id = pol.product_id
JOIN dim_branch b ON b.branch_id = pol.branch_id
LEFT JOIN fact_claims c ON c.policy_id = pol.policy_id
GROUP BY p.product_name, p.product_category, b.region, year(pol.effective_date), quarter(pol.effective_date);

CREATE OR REPLACE VIEW vw_branch_performance AS
SELECT
  b.branch_name, b.region, b.state,
  year(pol.effective_date) AS year_num,
  quarter(pol.effective_date) AS quarter_num,
  COUNT(*) AS new_policies,
  SUM(pol.premium_amount) AS total_premium,
  ROUND(AVG(pol.premium_amount), 2) AS avg_premium
FROM fact_policies pol
JOIN dim_branch b ON b.branch_id = pol.branch_id
GROUP BY b.branch_name, b.region, b.state, year(pol.effective_date), quarter(pol.effective_date);

CREATE OR REPLACE VIEW vw_claims_trend AS
SELECT
  p.product_name,
  year(c.claim_date) AS year_num,
  quarter(c.claim_date) AS quarter_num,
  c.claim_status,
  COUNT(*) AS claim_count,
  SUM(c.claim_amount_paid) AS total_paid
FROM fact_claims c
JOIN dim_product p ON p.product_id = c.product_id
GROUP BY p.product_name, year(c.claim_date), quarter(c.claim_date), c.claim_status;

-- ── Documentation (the "business glossary" your AI reads) ────────────────
COMMENT ON TABLE vw_loss_ratio_summary IS
  'Canonical loss ratio view - one row per product/region/quarter. loss_ratio_pct = total claims paid / total premium, the standard insurance loss ratio metric. Use this for any loss ratio, premium, or claims-frequency question.';
COMMENT ON TABLE vw_branch_performance IS
  'New-business branch performance - policy counts and premium volume by branch/quarter. Use for branch or region growth questions, not claims/loss questions.';
COMMENT ON TABLE vw_claims_trend IS
  'Claim counts and paid amounts by product/quarter/status (open, closed, denied). Use for claims-status or claims-volume breakdowns specifically; use vw_loss_ratio_summary for one overall loss ratio instead.';

-- ── Quick sanity check — run this after everything above finishes ────────
SELECT 'fact_policies' AS table_name, COUNT(*) AS row_count FROM fact_policies
UNION ALL
SELECT 'fact_claims', COUNT(*) FROM fact_claims
UNION ALL
SELECT 'vw_loss_ratio_summary', COUNT(*) FROM vw_loss_ratio_summary
UNION ALL
SELECT 'vw_branch_performance', COUNT(*) FROM vw_branch_performance
UNION ALL
SELECT 'vw_claims_trend', COUNT(*) FROM vw_claims_trend;
