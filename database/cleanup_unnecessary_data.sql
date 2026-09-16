-- ============================================================================
-- SAFE tenant cleanup — review first, delete only what you explicitly list
-- ============================================================================
-- The previous version of this file ("keep exactly these 3 hardcoded
-- names, delete everything else") caused real data loss: a real,
-- renamed tenant didn't match the hardcoded keep-list and was deleted
-- along with genuine junk. A SECOND version of this file then made
-- tenant deletion explicit/opt-in (good) but still swept up orphaned
-- schemas unconditionally (Part 3) — which caused a SECOND round of
-- data loss when it destroyed schemas from the FIRST incident before
-- they'd been recovered yet. Nothing in this file deletes ANYTHING
-- anymore without an explicit, human-reviewed opt-in list — not tenant
-- rows, not orphaned schemas.
--
-- ALWAYS take a fresh backup before running Part 2 or Part 4, no matter
-- how confident you are in either list.
-- ============================================================================


-- ============================================================================
-- PART 1 — Review only. Changes nothing. Run this first, always.
-- ============================================================================
-- Look at every tenant on the platform with enough context to actually
-- judge which ones are real and which are junk — don't rely on the name
-- alone (a real tenant can be renamed; a junk one can be named
-- convincingly during testing).
SELECT
    t.id,
    t.name,
    t.industry,
    t.is_active,
    t.created_at,
    t.schema_name,
    (SELECT count(*) FROM users u WHERE u.tenant_id = t.id) AS user_count,
    (SELECT max(created_at) FROM audit_log a WHERE a.tenant_id = t.id) AS last_activity
FROM tenants t
ORDER BY t.created_at;

-- Read this output carefully. For each tenant, ask: "do I recognize
-- this as something I actually created and use?" If yes, it is NOT a
-- candidate for deletion, regardless of what it's named or when it was
-- created. Only rows you are certain are throwaway test data belong in
-- Part 2 below.


-- ============================================================================
-- PART 2 — Explicit, opt-in deletion. Edit the id list, then run.
-- ============================================================================
-- Replace the ids below with ONLY the tenant ids from Part 1's output
-- that you have personally confirmed are junk. This starts empty on
-- purpose — nothing is deleted until you deliberately put ids here.
DO $$
DECLARE
    -- <<< EDIT THIS LIST — leave empty to delete nothing >>>
    ids_to_delete UUID[] := ARRAY[]::UUID[];
    t RECORD;
BEGIN
    IF array_length(ids_to_delete, 1) IS NULL THEN
        RAISE NOTICE 'No tenant ids listed — nothing will be deleted. Edit ids_to_delete above and re-run if you intend to delete something.';
        RETURN;
    END IF;

    FOR t IN SELECT id, name FROM tenants WHERE id = ANY(ids_to_delete) LOOP
        RAISE NOTICE 'Deleting tenant: % (%)', t.name, t.id;
        PERFORM delete_company_for_admin(t.id);
    END LOOP;

    -- Report any id in the list that didn't match a real tenant, so a
    -- typo doesn't silently do nothing without you noticing.
    IF EXISTS (
        SELECT 1 FROM unnest(ids_to_delete) AS wanted_id
        WHERE wanted_id NOT IN (SELECT id FROM tenants)
    ) THEN
        RAISE WARNING 'Some ids in the list did not match any tenant (already deleted, or a typo) — double check.';
    END IF;
END;
$$;


-- ============================================================================
-- PART 3 — Orphaned schema REVIEW only. Changes nothing by itself.
-- ============================================================================
-- Earlier versions of this file dropped orphaned schemas unconditionally
-- here, on the reasoning that "a schema with no tenant row can't be a
-- real, reachable tenant." That reasoning is correct on its own — but it
-- assumed any orphan found was ALREADY fully accounted for. In practice,
-- an orphan can exist precisely BECAUSE a tenant's row was deleted
-- moments ago and hasn't been recovered yet — running this unconditionally
-- destroyed exactly that kind of not-yet-recovered data. Like Part 1,
-- this now only lists what it finds; nothing is dropped without an
-- explicit, reviewed opt-in list, same as Part 2.
SELECT nspname AS orphaned_schema_name
FROM pg_namespace
WHERE nspname ~ '^tenant_[0-9a-f]{32}$'
  AND nspname NOT IN (SELECT schema_name FROM tenants)
ORDER BY nspname;

-- For EVERY schema name listed above, stop and ask yourself: "was this
-- tenant deleted on purpose, and have I already extracted anything I
-- need from it (or confirmed I don't need to)?" Only once you're sure
-- does a schema belong in the list below.


-- ============================================================================
-- PART 4 — Explicit, opt-in orphan schema deletion. Edit the list, then run.
-- ============================================================================
DO $$
DECLARE
    -- <<< EDIT THIS LIST — leave empty to delete nothing >>>
    schemas_to_drop TEXT[] := ARRAY[]::TEXT[];
    s TEXT;
BEGIN
    IF array_length(schemas_to_drop, 1) IS NULL THEN
        RAISE NOTICE 'No schema names listed — nothing will be dropped.';
        RETURN;
    END IF;

    FOREACH s IN ARRAY schemas_to_drop LOOP
        IF s !~ '^tenant_[0-9a-f]{32}$' OR s IN (SELECT schema_name FROM tenants) THEN
            RAISE WARNING 'Refusing to drop % — not a valid orphan schema name (either malformed, or a tenant still references it)', s;
            CONTINUE;
        END IF;
        RAISE NOTICE 'Dropping orphaned schema: %', s;
        EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', s);
    END LOOP;
END;
$$;


-- ── Confirm the end state ─────────────────────────────────────────────────
SELECT name, industry, schema_name FROM tenants ORDER BY name;
SELECT display_name, email, is_active FROM users ORDER BY tenant_id, display_name;
