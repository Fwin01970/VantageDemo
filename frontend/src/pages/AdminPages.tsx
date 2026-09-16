import { useEffect, useState } from "react";
import {
  fetchCompanies, createCompany, updateCompany, setCompanyActive, deleteCompany,
  fetchUsers, createUser, updateUser, setUserActive, deleteUser, resetUserPassword,
  fetchQueryParameters, saveQueryParameters,
  fetchAdminAuditLog,
  fetchTenantRoles, fetchUserRoles, setUserPermissions,
  Company, AdminUser, QueryParameterConnection, AdminAuditEntry, ApiError,
} from "../lib/api";
import ConfirmDialog from "../components/ConfirmDialog";

// Master Admin — real platform administration, not a testing convenience.
// Every action here writes through backend/app/routers/admin.py's
// SECURITY DEFINER functions into the TARGET tenant's own private schema
// (database/move_query_parameters_to_tenant_schema.sql) — nothing here
// touches Ask AI, Genie, or Use Cases; this manages platform structure
// only (tenants, users, query connections, audit).
//
// Each export below is a fully independent top-level PAGE, not a tab
// inside one shared "Admin" screen — AppShell.tsx renders each one as
// its own item directly in the main menu bar, visible to Super Admin
// only, the same way Ask AI or Dashboards are their own top-level items
// for an ordinary user. Every page loads its own data rather than
// sharing state through a parent wrapper, matching how every other
// top-level page in this app (ChatPage, GeniePage, etc.) already works.

interface PageProps {
  token: string;
  sessionExpired: boolean;
  onSessionExpired: () => void;
}

const PLATFORM_TENANT_ID = "00000000-0000-0000-0000-000000000000";

// ============================================================================
// Tenants — create (with optional initial query parameters right away) +
// list with inline edit / enable-disable / delete.
// ============================================================================
export function TenantsPage({ token, sessionExpired, onSessionExpired }: PageProps) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  function loadCompanies() {
    fetchCompanies(token)
      .then(setCompanies)
      .catch((e: ApiError) => {
        if (e.status === 401) onSessionExpired();
        setLoadError(e.message);
      });
  }
  useEffect(loadCompanies, [token]);

  const [name, setName] = useState("");
  const [industry, setIndustry] = useState("insurance");
  const [includeQp, setIncludeQp] = useState(false);
  const [qpHost, setQpHost] = useState("");
  const [qpWarehouse, setQpWarehouse] = useState("");
  const [qpCatalog, setQpCatalog] = useState("");
  const [qpSchema, setQpSchema] = useState("");
  const [qpSecretRef, setQpSecretRef] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Company | null>(null);

  async function handleCreate() {
    if (!name.trim() || busy || sessionExpired) return;
    setBusy(true);
    setMsg(null);
    try {
      const c = await createCompany(token, name.trim(), industry);
      if (includeQp && qpHost.trim()) {
        await saveQueryParameters(token, c.id, {
          platform: "databricks", host: qpHost.trim(), warehouse_id: qpWarehouse.trim(),
          catalog: qpCatalog.trim(), schema_name: qpSchema.trim(), secret_ref: qpSecretRef.trim(),
          is_active: true,
        });
      }
      setMsg(`Created "${c.name}" — its own private database schema was generated automatically.`);
      setName(""); setQpHost(""); setQpWarehouse(""); setQpCatalog(""); setQpSchema(""); setQpSecretRef("");
      setIncludeQp(false);
      loadCompanies();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  async function confirmDelete() {
    if (!deleteTarget) return;
    try {
      await deleteCompany(token, deleteTarget.id);
      setDeleteTarget(null);
      loadCompanies();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
    }
  }

  return (
    <div style={styles.page}>
      <PageHeader title="Tenants" sessionExpired={sessionExpired} loadError={loadError} />

      <section style={styles.card}>
        <div style={styles.cardTitle}>Add a tenant</div>
        <label style={styles.label}>Company name</label>
        <input style={styles.input} value={name} disabled={sessionExpired}
          onChange={(e) => setName(e.target.value)} placeholder="e.g. Northwind Healthcare" />
        <label style={styles.label}>Industry</label>
        <select style={styles.input} value={industry} disabled={sessionExpired} onChange={(e) => setIndustry(e.target.value)}>
          <option value="insurance">Insurance</option>
          <option value="banking">Banking</option>
          <option value="healthcare">Healthcare</option>
          <option value="financial_services">Financial Services</option>
          <option value="retail">Retail</option>
          <option value="other">Other</option>
        </select>

        <label style={styles.checkboxRow}>
          <input type="checkbox" checked={includeQp} disabled={sessionExpired} onChange={(e) => setIncludeQp(e.target.checked)} />
          Set up its Databricks connection now (optional — can also be added later from the Query Parameters page)
        </label>
        {includeQp && (
          <div style={styles.qpGrid}>
            <input style={styles.input} placeholder="Databricks host" value={qpHost} onChange={(e) => setQpHost(e.target.value)} />
            <input style={styles.input} placeholder="Warehouse ID" value={qpWarehouse} onChange={(e) => setQpWarehouse(e.target.value)} />
            <input style={styles.input} placeholder="Catalog" value={qpCatalog} onChange={(e) => setQpCatalog(e.target.value)} />
            <input style={styles.input} placeholder="Schema" value={qpSchema} onChange={(e) => setQpSchema(e.target.value)} />
            <input style={styles.input} placeholder="Secret reference (env var name)" value={qpSecretRef} onChange={(e) => setQpSecretRef(e.target.value)} />
          </div>
        )}

        <button style={styles.btn} onClick={handleCreate} disabled={busy || sessionExpired}>
          {busy ? "Creating…" : "Create tenant"}
        </button>
        {msg && <div style={styles.msg}>{msg}</div>}
      </section>

      <div style={styles.listCard}>
        <div style={styles.cardTitle}>Tenants on this platform</div>
        {companies.map((c) => {
          // Same exact ID the backend itself uses to refuse deleting this
          // tenant (add_platform_admin.sql) — checked here too, not just
          // by name/industry, so this can't be fooled and stays in
          // lockstep with the backend's own definition of "untouchable."
          const isPlatformTenant = c.id === PLATFORM_TENANT_ID;
          return (
            <div key={c.id}>
              <div style={styles.rowLine}>
                <div>
                  <span style={{ fontWeight: 600 }}>{c.name}</span>{" "}
                  <span style={{ color: "var(--ink-soft)" }}>· {c.industry}</span>
                  {isPlatformTenant && <span style={styles.internalTag}>Internal — not a customer</span>}
                </div>
                <div style={styles.rowActions}>
                  {!isPlatformTenant && (
                    <button style={styles.smallBtn} onClick={() => setExpandedId(expandedId === c.id ? null : c.id)}>
                      {expandedId === c.id ? "Close" : "Manage"}
                    </button>
                  )}
                  {/* The internal platform tenant holds every Super Admin
                      account — this button doesn't even render for it,
                      rather than rendering disabled or relying only on
                      the backend's own refusal to catch a misclick. */}
                  {!isPlatformTenant && (
                    <button style={styles.dangerSmallBtn} onClick={() => setDeleteTarget(c)}>Delete</button>
                  )}
                </div>
              </div>
              {expandedId === c.id && (
                <TenantDetailPanel
                  token={token} company={c} sessionExpired={sessionExpired}
                  onSessionExpired={onSessionExpired} onChanged={loadCompanies}
                />
              )}
            </div>
          );
        })}
      </div>

      {deleteTarget && (
        <ConfirmDialog
          title={`Delete "${deleteTarget.name}"?`}
          message="This permanently removes the tenant, every one of its users, and its entire private database schema. This can't be undone."
          confirmLabel="Delete tenant"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}
    </div>
  );
}

// Rename/re-industry only — Query Parameters now has its own dedicated
// page (see QueryParametersPage below), so this stays focused on the
// tenant's basic identity rather than duplicating the connection form
// in two places.
function TenantDetailPanel({
  token, company, sessionExpired, onSessionExpired, onChanged,
}: {
  token: string; company: Company; sessionExpired: boolean;
  onSessionExpired: () => void; onChanged: () => void;
}) {
  const [name, setName] = useState(company.name);
  const [industry, setIndustry] = useState(company.industry);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSaveDetails() {
    setBusy(true);
    setMsg(null);
    try {
      await updateCompany(token, company.id, name.trim(), industry);
      setMsg("Saved.");
      onChanged();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={styles.detailPanel}>
      <div style={styles.detailSectionTitle}>Tenant details</div>
      <div style={styles.qpGrid}>
        <input style={styles.input} value={name} disabled={sessionExpired} onChange={(e) => setName(e.target.value)} placeholder="Name" />
        <select style={styles.input} value={industry} disabled={sessionExpired} onChange={(e) => setIndustry(e.target.value)}>
          <option value="insurance">Insurance</option>
          <option value="banking">Banking</option>
          <option value="healthcare">Healthcare</option>
          <option value="financial_services">Financial Services</option>
          <option value="retail">Retail</option>
          <option value="other">Other</option>
        </select>
      </div>
      <button style={styles.smallBtn} onClick={handleSaveDetails} disabled={busy || sessionExpired}>Save details</button>
      {msg && <div style={styles.msg}>{msg}</div>}
      <div style={styles.hintInline}>Manage its Databricks connection from the Query Parameters page.</div>
    </div>
  );
}

// ============================================================================
// Users — create + list with disable/enable/delete/reset-password
// ============================================================================
export function UsersPage({ token, sessionExpired, onSessionExpired }: PageProps) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [users, setUsersList] = useState<AdminUser[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  function loadUsers() {
    fetchUsers(token).then(setUsersList).catch((e: ApiError) => {
      if (e.status === 401) onSessionExpired();
      setLoadError(e.message);
    });
  }
  useEffect(() => {
    fetchCompanies(token).then(setCompanies).catch(() => {});
    loadUsers();
  }, [token]);

  const [tenantId, setTenantId] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [resetMsg, setResetMsg] = useState<{ userId: string; password: string } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<AdminUser | null>(null);

  useEffect(() => {
    if (!tenantId && companies.length > 0) setTenantId(companies[0].id);
  }, [companies]);

  async function handleCreate() {
    if (!displayName.trim() || !email.trim() || !tenantId || busy || sessionExpired) return;
    setBusy(true);
    setMsg(null);
    try {
      await createUser(token, tenantId, displayName.trim(), email.trim());
      setMsg(`Created ${displayName} — they can sign in immediately.`);
      setDisplayName(""); setEmail("");
      loadUsers();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  async function handleToggleActive(u: AdminUser) {
    try {
      await setUserActive(token, u.id, !u.is_active);
      loadUsers();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
    }
  }

  async function handleReset(u: AdminUser) {
    try {
      const r = await resetUserPassword(token, u.id);
      setResetMsg({ userId: u.id, password: r.temporary_password });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
    }
  }

  async function confirmDelete() {
    if (!deleteTarget) return;
    try {
      await deleteUser(token, deleteTarget.id);
      setDeleteTarget(null);
      loadUsers();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
    }
  }

  return (
    <div style={styles.page}>
      <PageHeader title="Users" sessionExpired={sessionExpired} loadError={loadError} />

      <section style={styles.card}>
        <div style={styles.cardTitle}>Add a user</div>
        <label style={styles.label}>Tenant</label>
        <select style={styles.input} value={tenantId} disabled={sessionExpired} onChange={(e) => setTenantId(e.target.value)}>
          {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <label style={styles.label}>Display name</label>
        <input style={styles.input} value={displayName} disabled={sessionExpired} onChange={(e) => setDisplayName(e.target.value)} placeholder="e.g. Priya Nair" />
        <label style={styles.label}>Email</label>
        <input style={styles.input} value={email} disabled={sessionExpired} onChange={(e) => setEmail(e.target.value)} placeholder="e.g. priya.nair@company.com" />
        <button style={styles.btn} onClick={handleCreate} disabled={busy || sessionExpired}>
          {busy ? "Creating…" : "Create user"}
        </button>
        {msg && <div style={styles.msg}>{msg}</div>}
      </section>

      <div style={styles.listCard}>
        <div style={styles.cardTitle}>Users on this platform</div>
        {users.map((u) => (
          <div key={u.id} style={styles.rowLine}>
            <div>
              <span style={{ fontWeight: 600 }}>{u.display_name}</span>{" "}
              <span style={{ color: "var(--ink-soft)" }}>· {u.email} · {u.tenant_name}</span>
              {!u.is_active && <span style={styles.inactiveTag}>disabled</span>}
              {resetMsg?.userId === u.id && (
                <div style={styles.tempPasswordNote}>
                  Temporary password (shown once): <code style={styles.code}>{resetMsg.password}</code>
                </div>
              )}
            </div>
            <div style={styles.rowActions}>
              <button style={styles.smallBtn} onClick={() => handleReset(u)}>Reset password</button>
              <button style={styles.smallBtn} onClick={() => handleToggleActive(u)}>{u.is_active ? "Disable" : "Enable"}</button>
              <button style={styles.dangerSmallBtn} onClick={() => setDeleteTarget(u)}>Delete</button>
            </div>
          </div>
        ))}
      </div>

      {deleteTarget && (
        <ConfirmDialog
          title={`Delete ${deleteTarget.display_name}?`}
          message="This permanently removes their account. This can't be undone."
          confirmLabel="Delete user"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}
    </div>
  );
}

// ============================================================================
// Audit Log — tenant-wise (and optionally user-wise) filterable feed
// ============================================================================
export function AuditLogPage({ token, sessionExpired }: PageProps) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [users, setUsersList] = useState<AdminUser[]>([]);
  const [tenantId, setTenantId] = useState<string>("");
  const [userId, setUserId] = useState<string>("");
  const [entries, setEntries] = useState<AdminAuditEntry[] | null>(null);

  useEffect(() => {
    fetchCompanies(token).then(setCompanies).catch(() => {});
    fetchUsers(token).then(setUsersList).catch(() => {});
  }, [token]);

  useEffect(() => {
    fetchAdminAuditLog(token, tenantId || undefined, userId || undefined).then(setEntries).catch(() => setEntries([]));
  }, [token, tenantId, userId]);

  const usersForTenant = tenantId ? users.filter((u) => u.tenant_id === tenantId) : users;

  return (
    <div style={styles.page}>
      <PageHeader title="Audit Log" sessionExpired={sessionExpired} loadError={null} />

      <div style={styles.filterRow}>
        <select style={styles.input} value={tenantId} onChange={(e) => { setTenantId(e.target.value); setUserId(""); }}>
          <option value="">All tenants</option>
          {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select style={styles.input} value={userId} onChange={(e) => setUserId(e.target.value)}>
          <option value="">All users</option>
          {usersForTenant.map((u) => <option key={u.id} value={u.id}>{u.display_name}</option>)}
        </select>
      </div>

      <div style={styles.listCard}>
        {entries === null && <div style={styles.hint}>Loading…</div>}
        {entries?.length === 0 && <div style={styles.hint}>No activity found for this filter.</div>}
        {entries?.map((e) => (
          <div key={e.id} style={styles.auditRow}>
            <div style={styles.auditAction}>{e.action}</div>
            <div style={styles.auditMeta}>
              {e.tenant_name}{e.user_display_name ? ` · ${e.user_display_name}` : ""} · {new Date(e.created_at).toLocaleString()}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ============================================================================
// Query Parameters — pick a tenant, view/edit its Databricks connection.
// Now its own page (was previously buried inside a tenant's "Manage"
// panel on the Tenants page) — writes through the same
// upsert_data_source_connection_for_admin, into that tenant's OWN
// private schema, never a shared public table.
// ============================================================================
export function QueryParametersPage({ token, sessionExpired, onSessionExpired }: PageProps) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [tenantId, setTenantId] = useState("");
  const [qp, setQp] = useState<QueryParameterConnection | null>(null);
  const [qpHost, setQpHost] = useState("");
  const [qpWarehouse, setQpWarehouse] = useState("");
  const [qpCatalog, setQpCatalog] = useState("");
  const [qpSchema, setQpSchema] = useState("");
  const [qpSecretRef, setQpSecretRef] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    fetchCompanies(token).then((cs) => {
      // The internal platform tenant has no Databricks data of its own —
      // exclude it here so it's never accidentally selected and given a
      // connection that has nothing meaningful to query.
      const real = cs.filter((c) => c.id !== PLATFORM_TENANT_ID);
      setCompanies(real);
      if (real.length > 0) setTenantId(real[0].id);
    }).catch((e: ApiError) => {
      if (e.status === 401) onSessionExpired();
    });
  }, [token]);

  useEffect(() => {
    if (!tenantId) return;
    fetchQueryParameters(token, tenantId).then((rows) => {
      const existing = rows.find((r) => r.platform === "databricks") ?? null;
      setQp(existing);
      setQpHost(existing?.config.host ?? "");
      setQpWarehouse(existing?.config.warehouse_id ?? "");
      setQpCatalog(existing?.config.catalog ?? "");
      setQpSchema(existing?.config.schema ?? "");
      setQpSecretRef(existing?.secret_ref ?? "");
      setMsg(null);
    });
  }, [token, tenantId]);

  async function handleSave() {
    setBusy(true);
    setMsg(null);
    try {
      const saved = await saveQueryParameters(token, tenantId, {
        platform: "databricks", host: qpHost.trim(), warehouse_id: qpWarehouse.trim(),
        catalog: qpCatalog.trim(), schema_name: qpSchema.trim(), secret_ref: qpSecretRef.trim(),
        is_active: true,
      });
      setQp(saved);
      setMsg(qp ? "Query parameters updated." : "Query parameters added.");
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={styles.page}>
      <PageHeader title="Query Parameters" sessionExpired={sessionExpired} loadError={null} />

      <section style={styles.card}>
        <label style={styles.label}>Tenant</label>
        <select style={styles.input} value={tenantId} disabled={sessionExpired} onChange={(e) => setTenantId(e.target.value)}>
          {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>

        <div style={{ ...styles.cardTitle, marginTop: 18 }}>
          Databricks connection {qp && <span style={styles.hintInline}>(editing existing connection)</span>}
        </div>
        <div style={styles.qpGrid}>
          <input style={styles.input} placeholder="Databricks host" value={qpHost} disabled={sessionExpired} onChange={(e) => setQpHost(e.target.value)} />
          <input style={styles.input} placeholder="Warehouse ID" value={qpWarehouse} disabled={sessionExpired} onChange={(e) => setQpWarehouse(e.target.value)} />
          <input style={styles.input} placeholder="Catalog" value={qpCatalog} disabled={sessionExpired} onChange={(e) => setQpCatalog(e.target.value)} />
          <input style={styles.input} placeholder="Schema" value={qpSchema} disabled={sessionExpired} onChange={(e) => setQpSchema(e.target.value)} />
          <input style={styles.input} placeholder="Secret reference (env var name)" value={qpSecretRef} disabled={sessionExpired} onChange={(e) => setQpSecretRef(e.target.value)} />
        </div>
        <button style={styles.btn} onClick={handleSave} disabled={busy || sessionExpired || !tenantId}>
          {qp ? "Update query parameters" : "Add query parameters"}
        </button>
        {msg && <div style={styles.msg}>{msg}</div>}
      </section>
    </div>
  );
}

// ============================================================================
// Manage Tabs — NOT YET BUILT. Placeholder so Super Admin can see this is
// coming, rather than the menu item silently not existing.
// ============================================================================
export function ManageTabsPage({ token, sessionExpired, onSessionExpired }: PageProps) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [users, setUsersList] = useState<AdminUser[]>([]);
  const [userId, setUserId] = useState("");
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // A fixed, small set — these are the only permissions that actually
  // gate a top-level tab in the app today (see AppShell.tsx). Not every
  // row in the full permission catalog belongs here (tenant:manage also
  // controls Use Cases authoring, audit:view/governance:manage control
  // Governance panel visibility, not a whole separate tab) — kept
  // explicit and named after what the person actually sees, not the raw
  // permission code, since that's what a Super Admin is really deciding.
  const TAB_PERMISSIONS: { code: string; label: string }[] = [
    { code: "data:query", label: "Ask AI" },
    { code: "genie:access", label: "Genie" },
    { code: "tenant:manage", label: "Use Cases" },
  ];

  useEffect(() => {
    fetchCompanies(token).then((cs) => setCompanies(cs.filter((c) => c.id !== PLATFORM_TENANT_ID))).catch(() => {});
    fetchUsers(token).then(setUsersList).catch((e: ApiError) => { if (e.status === 401) onSessionExpired(); });
  }, [token]);

  useEffect(() => {
    if (!userId) return;
    fetchUserRoles(token, userId).then(async (roles) => {
      // Union of every permission across every role this user currently
      // has — a user usually has exactly one role (the tenant's shared
      // "Team Member", or a personal one from a previous Manage Tabs
      // save), but this stays correct either way.
      const allTenantRoles = await Promise.all(
        companies.map((c) => fetchTenantRoles(token, c.id).catch(() => []))
      );
      const flatRoles = allTenantRoles.flat();
      const activeCodes = new Set<string>();
      for (const r of roles) {
        const match = flatRoles.find((tr) => tr.id === r.role_id);
        match?.permission_codes.forEach((code: string) => activeCodes.add(code));
      }
      const next: Record<string, boolean> = {};
      for (const t of TAB_PERMISSIONS) next[t.code] = activeCodes.has(t.code);
      setChecked(next);
    });
  }, [token, userId, companies]);

  async function handleSave() {
    const user = users.find((u) => u.id === userId);
    if (!user) return;
    setBusy(true);
    setMsg(null);
    try {
      const codes = TAB_PERMISSIONS.filter((t) => checked[t.code]).map((t) => t.code);
      await setUserPermissions(token, userId, user.tenant_id, codes);
      setMsg(`Saved — ${user.display_name} will see exactly these tabs next time they load the app.`);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={styles.page}>
      <PageHeader title="Manage Tabs" sessionExpired={sessionExpired} loadError={null} />

      <section style={styles.card}>
        <label style={styles.label}>User</label>
        <select style={styles.input} value={userId} disabled={sessionExpired} onChange={(e) => setUserId(e.target.value)}>
          <option value="">Select a user…</option>
          {users.map((u) => <option key={u.id} value={u.id}>{u.display_name} ({u.tenant_name})</option>)}
        </select>

        {userId && (
          <>
            <div style={{ ...styles.cardTitle, marginTop: 18 }}>Tabs this user can see</div>
            {TAB_PERMISSIONS.map((t) => (
              <label key={t.code} style={styles.checkboxRow}>
                <input
                  type="checkbox"
                  checked={checked[t.code] ?? false}
                  disabled={sessionExpired}
                  onChange={(e) => setChecked((prev) => ({ ...prev, [t.code]: e.target.checked }))}
                />
                {t.label}
              </label>
            ))}
            <button style={styles.btn} onClick={handleSave} disabled={busy || sessionExpired}>
              {busy ? "Saving…" : "Save"}
            </button>
            {msg && <div style={styles.msg}>{msg}</div>}
          </>
        )}
      </section>
    </div>
  );
}

// ============================================================================
// Manage Schema & Tables — NOT YET BUILT. Placeholder.
// ============================================================================
export function ManageSchemaTablesPage({ sessionExpired }: PageProps) {
  return (
    <div style={styles.page}>
      <PageHeader title="Manage Schema & Tables" sessionExpired={sessionExpired} loadError={null} />
      <ComingSoon
        description="Browse each tenant's real Databricks schemas/tables (kept in sync automatically as new ones appear) and control which specific schema/table a user can query. If a schema or table hasn't been granted to the app's own Databricks identity yet, this will say so clearly (\u201cPlease first grant access from Databricks RBAC\u201d) rather than silently failing."
      />
    </div>
  );
}

function ComingSoon({ description }: { description: string }) {
  return (
    <div style={styles.card}>
      <div style={styles.cardTitle}>Coming soon</div>
      <div style={{ fontSize: 13.5, color: "var(--ink)", lineHeight: 1.6 }}>{description}</div>
    </div>
  );
}

function PageHeader({ title, sessionExpired, loadError }: { title: string; sessionExpired: boolean; loadError: string | null }) {
  return (
    <>
      <div style={styles.pageTitle}>{title}</div>
      {sessionExpired && (
        <div style={styles.expiredNote}>
          Your session has expired — sign in again (top right) to make changes.
        </div>
      )}
      {loadError && <div style={styles.errorNote}>{loadError}</div>}
    </>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { maxWidth: 960, margin: "0 auto", padding: "32px 24px 60px" },
  pageTitle: { fontSize: 20, fontWeight: 700, color: "var(--ink)", marginBottom: 18 },
  expiredNote: { background: "#FFF7E6", border: "1px solid #F0C36D", borderRadius: 8, padding: "10px 14px", fontSize: 12.5, color: "#8A5A00", marginBottom: 20 },
  errorNote: { background: "var(--danger-soft)", border: "1px solid rgba(179,38,30,0.25)", borderRadius: 8, padding: "10px 14px", fontSize: 12.5, color: "var(--danger)", marginBottom: 20 },
  card: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 18, marginBottom: 20 },
  cardTitle: { fontSize: 11.5, fontFamily: "var(--mono)", letterSpacing: 0.5, textTransform: "uppercase", color: "var(--ink-soft)", marginBottom: 12 },
  label: { display: "block", fontSize: 12, fontWeight: 600, margin: "10px 0 5px" },
  input: { width: "100%", padding: "9px 11px", fontSize: 13.5, border: "1px solid var(--line)", borderRadius: 6, fontFamily: "var(--sans)", background: "var(--surface)", color: "var(--ink)" },
  checkboxRow: { display: "flex", alignItems: "center", gap: 8, fontSize: 12.5, color: "var(--ink-soft)", margin: "14px 0 8px" },
  qpGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, marginBottom: 10 },
  btn: { marginTop: 14, padding: "10px 18px", background: "var(--primary)", color: "white", border: "none", borderRadius: 6, fontWeight: 600, fontSize: 13.5, cursor: "pointer" },
  msg: { marginTop: 10, fontSize: 12.5, color: "var(--accent)", lineHeight: 1.5 },
  listCard: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 18 },
  rowLine: { display: "flex", justifyContent: "space-between", alignItems: "center", fontSize: 13, padding: "10px 0", borderBottom: "1px solid var(--line)" },
  rowActions: { display: "flex", gap: 6, flexShrink: 0 },
  smallBtn: { fontSize: 11.5, background: "none", border: "1px solid var(--line)", borderRadius: 6, padding: "5px 10px", cursor: "pointer", color: "var(--ink)" },
  dangerSmallBtn: { fontSize: 11.5, background: "none", border: "1px solid var(--danger)", borderRadius: 6, padding: "5px 10px", cursor: "pointer", color: "var(--danger)" },
  inactiveTag: { marginLeft: 8, fontSize: 10.5, fontWeight: 700, color: "var(--danger)", textTransform: "uppercase" },
  internalTag: { marginLeft: 8, fontSize: 10.5, fontWeight: 700, color: "var(--ink-soft)", textTransform: "uppercase" },
  tempPasswordNote: { marginTop: 6, fontSize: 12, color: "var(--ink-soft)" },
  code: { fontFamily: "var(--mono)", background: "var(--paper)", border: "1px solid var(--line)", borderRadius: 4, padding: "1px 6px" },
  detailPanel: { background: "var(--paper)", border: "1px solid var(--line)", borderRadius: 8, padding: 14, margin: "6px 0 14px" },
  detailSectionTitle: { fontSize: 11.5, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.4, color: "var(--ink-soft)", marginBottom: 8 },
  hintInline: { fontWeight: 400, textTransform: "none", letterSpacing: 0, fontSize: 11.5, color: "var(--ink-soft)", marginTop: 8 },
  filterRow: { display: "flex", gap: 10, marginBottom: 16 },
  hint: { fontSize: 13, color: "var(--ink-soft)" },
  auditRow: { padding: "10px 0", borderBottom: "1px solid var(--line)" },
  auditAction: { fontSize: 13, fontFamily: "var(--mono)", fontWeight: 600 },
  auditMeta: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 2 },
};
