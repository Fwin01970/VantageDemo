-- ============================================================================
-- Persist chart data with chat messages
-- ============================================================================
-- Previously the columns/rows behind a chart shown in Ask AI existed only
-- in the API response for that one request — never saved. Reopening an
-- older conversation re-fetched only role/content from chat_messages, so
-- the chart disappeared (only the LLM's own prose/markdown remained).
-- This adds a nullable JSONB column so the SAME columns/rows used to
-- render the chart the first time are available again on reload, instead
-- of nothing (or the model's own inconsistent redraw of the same data).
-- ============================================================================

ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS chart_data JSONB;
