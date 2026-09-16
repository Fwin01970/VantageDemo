-- ============================================================================
-- Drop superseded public-schema tables
-- ============================================================================
-- Each of these tables was moved into every tenant's own private schema
-- earlier (tenant_application_schemas.sql for user_credentials/
-- local_secrets, move_genie_config_to_tenant_schema.sql for Genie
-- config, move_query_parameters_to_tenant_schema.sql for Query
-- Parameters). Each move already REVOKEd ryze_app's access to the public
-- copy and kept the table itself around only as a safety margin during
-- the transition. Every real read/write path has since been confirmed
-- working against the tenant-schema versions (including under the
-- actual, non-superuser ryze_app role — see the RLS verification done
-- while building the Genie config move), so the leftover public copies
-- are now genuinely unnecessary data, not a safety net.
--
-- No foreign keys reference any of these tables (checked directly), so
-- this is a plain, safe DROP.
--
-- Run this last, after move_query_parameters_to_tenant_schema.sql.
-- ============================================================================

DROP TABLE IF EXISTS public.genie_query_parameter_fields;
DROP TABLE IF EXISTS public.genie_question_templates;
DROP TABLE IF EXISTS public.genie_suggested_questions;
DROP TABLE IF EXISTS public.data_source_connections;
DROP TABLE IF EXISTS public.user_credentials;
DROP TABLE IF EXISTS public.local_secrets;
