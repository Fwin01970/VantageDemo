-- ============================================================================
-- Governance: HITL (human-in-the-loop) review queue
-- ============================================================================
-- Backs the "Governance" panel's proxy-layer story: every question passes
-- through jailbreak/PII/fairness/scope checks (guardrails/engine.py +
-- llm_classifier.py) BEFORE it ever reaches an LLM or Databricks. Most
-- violations are unambiguous and get auto-blocked outright. Borderline
-- cases (low-confidence off-topic, for example) are neither answered nor
-- silently dropped — they land here for a human reviewer to actually see
-- and decide on, which is the point of HITL: uncertain cases get a human
-- in the loop instead of the system guessing either direction.
-- ============================================================================

CREATE TABLE IF NOT EXISTS governance_reviews (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id       UUID REFERENCES users(id),
    question      TEXT NOT NULL,
    check_type    TEXT NOT NULL,             -- e.g. 'off_topic', 'jailbreak_borderline'
    reason        TEXT NOT NULL DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
    reviewed_by   UUID REFERENCES users(id),
    reviewed_at   TIMESTAMPTZ,
    decision_note TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE governance_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_governance_reviews ON governance_reviews
    USING (tenant_id = current_tenant_id_safe());

CREATE INDEX IF NOT EXISTS idx_governance_reviews_tenant_status
    ON governance_reviews (tenant_id, status, created_at DESC);

-- New permission — separate from audit:view (read-only) because deciding
-- a HITL case is an action with consequences (it can be treated as a
-- precedent for similar future questions), not just visibility.
INSERT INTO permissions (code, description) VALUES
    ('governance:manage', 'Review and decide human-in-the-loop guardrail cases')
ON CONFLICT (code) DO NOTHING;

-- Grant it to the same role that already holds audit:view in the demo
-- tenant, so the existing demo login can actually exercise this in a
-- client demo without needing new seed users.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.code = 'governance:manage'
WHERE r.id IN (SELECT role_id FROM role_permissions rp JOIN permissions p2 ON p2.id = rp.permission_id WHERE p2.code = 'audit:view')
ON CONFLICT DO NOTHING;
