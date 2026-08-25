-- ── Schema Annotations — our own business glossary ──────────────────────
-- This is the alternative to writing COMMENT ON TABLE/COLUMN directly in
-- a client's Databricks workspace. A client's data team owns their
-- Databricks schema, and reasonably may not want us running DDL against
-- it — even documentation-only DDL like COMMENT statements. So instead,
-- the glossary lives ENTIRELY here, in our own database, tenant-scoped.
-- Databricks itself is never written to by anything related to this
-- table — only read, the same way table/column discovery already was.
--
-- column_name = NULL means the note describes the whole table.
-- column_name set means the note describes just that one column.

CREATE TABLE schema_annotations (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    catalog_name  TEXT NOT NULL,
    schema_name   TEXT NOT NULL,
    table_name    TEXT NOT NULL,
    column_name   TEXT,                    -- NULL = note is about the whole table
    note          TEXT NOT NULL,
    created_by    UUID REFERENCES users(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_schema_annotations_lookup
    ON schema_annotations (tenant_id, catalog_name, schema_name, table_name);

ALTER TABLE schema_annotations ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_schema_annotations ON schema_annotations
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
