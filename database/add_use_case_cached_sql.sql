-- ============================================================================
-- Cache the SQL a use case actually runs — write once at Preview/Save,
-- read on every subsequent Launch
-- ============================================================================
-- Previously, launching a saved use case re-ran the ENTIRE Ask AI
-- pipeline every single time (LLM writes SQL -> executes -> LLM
-- summarizes) even though the question never changes. That means every
-- launch cost real LLM tokens/latency and could fail outright on a
-- provider outage or quota limit (exactly what just happened) for
-- something that should be a deterministic, repeatable query.
--
-- Now the LLM only ever writes the SQL ONCE, when a use case is
-- previewed and saved. From then on, launching it re-runs that EXACT
-- SQL directly against the warehouse — no LLM call, no guardrail LLM
-- classifier, nothing that can rate-limit or go down.
-- ============================================================================

ALTER TABLE use_cases ADD COLUMN IF NOT EXISTS generated_sql TEXT;
