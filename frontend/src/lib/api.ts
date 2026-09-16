/**
 * Everything that talks to the backend lives here, in one place.
 * The backend address is the only thing that would change if this app
 * were ever pointed at a different environment — nothing else in the app
 * should need to know the URL.
 */
const API_BASE = "http://127.0.0.1:8000";

export interface DemoUser {
  id: string;
  display_name: string;
  email: string;
  tenant_name: string;
}

export interface MeResponse {
  user_id: string;
  display_name: string;
  email: string;
  tenant_id: string;
  tenant_name: string;
  industry: string;
  roles: string[];
  permissions: string[];
}

export interface GuardrailEvent {
  policy: string;
  detail: string;
}

export interface GroundingInfo {
  score: number;
  flagged: boolean;
}

export interface GenieResult {
  sql: string | null;
  summary: string | null;
  columns: string[];
  rows: (string | null)[][];
  row_count: number;
  conversation_id: string;
  message_id: string;
  guardrails: {
    input_events: GuardrailEvent[];
    llm_check: { ran: boolean; provider_used: string | null };
    grounding: GroundingInfo | null;
  };
}

export interface Company {
  id: string;
  name: string;
  industry: string;
}

export interface UseCase {
  id: string;
  title: string;
  description: string;
  category: string;
  sample_question: string;
  icon_key: string;
  generated_sql: string | null;
  has_cached_query: boolean;
}

export interface ConversationSummary {
  id: string;
  title: string;
  updated_at: string;
}

export interface StoredMessage {
  role: "user" | "assistant";
  content: string;
  chart_data?: ChatChartData | null;
}

export interface PinnedItem {
  id: string;
  source: string;
  item_type: "insight" | "table" | "chart";
  title: string;
  payload: any;
  created_at: string;
  is_mine: boolean;
  owner_name: string | null;
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ChatChartData {
  columns: string[];
  rows: any[][];
}

export interface ChatResponse {
  conversation_id: string;
  reply: string;
  tool_used: boolean;
  tool_question: string | null;
  provider_used: string | null;
  tool_available: boolean;
  blocked: boolean;
  blocked_events: GuardrailEvent[] | null;
  chart_data: ChatChartData | null;
  sql: string | null;
  guardrail_input_events: GuardrailEvent[];
  grounding: GroundingInfo | null;
}

// Structured error so the UI can tell a guardrail block (400, with
// policy detail) apart from a plain connection/permission failure.
export class ApiError extends Error {
  status: number;
  events?: GuardrailEvent[];
  constructor(message: string, status: number, events?: GuardrailEvent[]) {
    super(message);
    this.status = status;
    this.events = events;
  }
}

async function handle<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let detail = res.statusText;
    let events: GuardrailEvent[] | undefined;
    try {
      const body = await res.json();
      if (typeof body.detail === "string") {
        detail = body.detail;
      } else if (body.detail?.message) {
        detail = body.detail.message;
        events = body.detail.events;
      }
    } catch {
      /* response wasn't JSON — fall back to the status text above */
    }
    throw new ApiError(detail, res.status, events);
  }
  return res.json();
}

export async function fetchDemoUsers(): Promise<DemoUser[]> {
  const res = await fetch(`${API_BASE}/auth/demo-users`);
  return handle<DemoUser[]>(res);
}

export async function demoLogin(userId: string): Promise<string> {
  const res = await fetch(`${API_BASE}/auth/demo-login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user_id: userId }),
  });
  const data = await handle<{ access_token: string }>(res);
  return data.access_token;
}

export type OAuthProviderName = "microsoft" | "google" | "github" | "facebook";

export async function fetchAuthProviders(): Promise<Record<OAuthProviderName, boolean>> {
  const res = await fetch(`${API_BASE}/auth/providers`);
  return handle(res);
}

export function oauthStartUrl(provider: OAuthProviderName): string {
  return `${API_BASE}/auth/oauth/${provider}/start`;
}

export async function signup(data: {
  email: string; password: string; display_name: string; company_name: string; industry?: string;
}): Promise<string> {
  const res = await fetch(`${API_BASE}/auth/signup`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  const body = await handle<{ access_token: string }>(res);
  return body.access_token;
}

export async function loginWithPassword(email: string, password: string): Promise<string> {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const body = await handle<{ access_token: string }>(res);
  return body.access_token;
}

export async function fetchMe(token: string): Promise<MeResponse> {
  const res = await fetch(`${API_BASE}/me`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<MeResponse>(res);
}

export async function askGenie(token: string, question: string): Promise<GenieResult> {
  const res = await fetch(`${API_BASE}/data/ask-genie`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ question }),
  });
  return handle<GenieResult>(res);
}

// ── Governance: guardrail proxy-layer activity + HITL review queue ──────
// NOTE: fetchAuditLog / GET /audit/log was removed — raw audit history
// is Platform Super Admin-only now (see fetchAdminAuditLog above), not
// something an ordinary tenant user's Governance panel shows anymore.

export interface GuardrailActivityEntry {
  id: string;
  user_id: string | null;
  action: string;
  details: Record<string, any>;
  created_at: string;
}

export interface GuardrailInfo {
  name: string;
  stage: string;
  description: string;
  pattern_count?: number;
}

export interface HitlReview {
  id: string;
  question: string;
  check_type: string;
  reason: string;
  status: "pending" | "approved" | "rejected" | "hold";
  created_at: string;
  reviewed_at: string | null;
  decision_note: string | null;
  user_id: string | null;
  user_name: string | null;
  reviewed_by_name: string | null;
}

export async function fetchGuardrailActivity(token: string): Promise<GuardrailActivityEntry[]> {
  const res = await fetch(`${API_BASE}/governance/activity`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<GuardrailActivityEntry[]>(res);
}

export async function fetchGuardrailsInfo(token: string): Promise<GuardrailInfo[]> {
  const res = await fetch(`${API_BASE}/governance/guardrails-info`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<GuardrailInfo[]>(res);
}

export async function fetchHitlQueue(token: string, status?: string, userId?: string): Promise<HitlReview[]> {
  const params = new URLSearchParams();
  if (status) params.set("status", status);
  if (userId) params.set("user_id", userId);
  const qs = params.toString() ? `?${params}` : "";
  const res = await fetch(`${API_BASE}/governance/hitl${qs}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<HitlReview[]>(res);
}

export async function decideHitlCase(
  token: string, reviewId: string, decision: "approved" | "rejected" | "hold", note?: string
): Promise<{ id: string; status: string }> {
  const res = await fetch(`${API_BASE}/governance/hitl/${reviewId}/decision`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ decision, note: note ?? null }),
  });
  return handle<{ id: string; status: string }>(res);
}

// ── Platform Admin (testing convenience — see backend for the honest
// distinction between this and normal Tenant Admin capability) ─────────
export async function fetchCompanies(token: string): Promise<Company[]> {
  const res = await fetch(`${API_BASE}/admin/companies`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<Company[]>(res);
}

export async function createCompany(token: string, name: string, industry: string): Promise<Company> {
  const res = await fetch(`${API_BASE}/admin/companies`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name, industry }),
  });
  return handle<Company>(res);
}

export async function createUser(
  token: string,
  tenantId: string,
  displayName: string,
  email: string
): Promise<{ id: string; display_name: string; email: string }> {
  const res = await fetch(`${API_BASE}/admin/users`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ tenant_id: tenantId, display_name: displayName, email }),
  });
  return handle(res);
}

export interface AdminUser {
  id: string;
  tenant_id: string;
  tenant_name: string;
  display_name: string;
  email: string;
  is_active: boolean;
  created_at: string;
  last_login_at: string | null;
}

export interface QueryParameterConnection {
  id: string;
  platform: string;
  config: { host?: string; warehouse_id?: string; catalog?: string; schema?: string };
  secret_ref: string | null;
  is_active: boolean;
  created_at: string;
}

export interface AdminAuditEntry {
  id: string;
  tenant_id: string;
  tenant_name: string;
  user_id: string | null;
  user_display_name: string | null;
  action: string;
  details: Record<string, unknown>;
  created_at: string;
}

async function adminFetch<T>(token: string, path: string, opts: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...opts,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, ...(opts.headers ?? {}) },
  });
  return handle<T>(res);
}

export async function updateCompany(token: string, tenantId: string, name: string, industry: string): Promise<Company> {
  return adminFetch(token, `/admin/companies/${tenantId}`, { method: "PUT", body: JSON.stringify({ name, industry }) });
}

export async function setCompanyActive(token: string, tenantId: string, active: boolean): Promise<{ id: string; is_active: boolean }> {
  return adminFetch(token, `/admin/companies/${tenantId}/${active ? "enable" : "disable"}`, { method: "PUT" });
}

export async function deleteCompany(token: string, tenantId: string): Promise<void> {
  await adminFetch(token, `/admin/companies/${tenantId}`, { method: "DELETE" });
}

export async function fetchUsers(token: string): Promise<AdminUser[]> {
  return adminFetch(token, "/admin/users");
}

export async function updateUser(token: string, userId: string, displayName: string, email: string): Promise<AdminUser> {
  return adminFetch(token, `/admin/users/${userId}`, { method: "PUT", body: JSON.stringify({ display_name: displayName, email }) });
}

export async function setUserActive(token: string, userId: string, active: boolean): Promise<{ id: string; is_active: boolean }> {
  return adminFetch(token, `/admin/users/${userId}/${active ? "enable" : "disable"}`, { method: "PUT" });
}

export async function deleteUser(token: string, userId: string): Promise<void> {
  await adminFetch(token, `/admin/users/${userId}`, { method: "DELETE" });
}

export async function resetUserPassword(token: string, userId: string): Promise<{ id: string; temporary_password: string }> {
  return adminFetch(token, `/admin/users/${userId}/reset-password`, { method: "POST" });
}

export async function fetchQueryParameters(token: string, tenantId: string): Promise<QueryParameterConnection[]> {
  return adminFetch(token, `/admin/tenants/${tenantId}/query-parameters`);
}

export async function saveQueryParameters(
  token: string, tenantId: string,
  data: { platform: string; host?: string; warehouse_id?: string; catalog?: string; schema_name?: string; secret_ref?: string; is_active: boolean }
): Promise<QueryParameterConnection> {
  return adminFetch(token, `/admin/tenants/${tenantId}/query-parameters`, { method: "PUT", body: JSON.stringify(data) });
}

export async function deleteQueryParameters(token: string, connectionId: string): Promise<void> {
  await adminFetch(token, `/admin/query-parameters/${connectionId}`, { method: "DELETE" });
}

export async function fetchTenantRoles(token: string, tenantId: string): Promise<{ id: string; name: string; permission_codes: string[]; user_count: number }[]> {
  return adminFetch(token, `/admin/tenants/${tenantId}/roles`);
}

export async function fetchUserRoles(token: string, userId: string): Promise<{ role_id: string; role_name: string }[]> {
  return adminFetch(token, `/admin/users/${userId}/roles`);
}

export async function fetchAllPermissions(token: string): Promise<{ id: string; code: string; description: string }[]> {
  return adminFetch(token, `/admin/permissions`);
}

export async function setUserPermissions(
  token: string, userId: string, tenantId: string, permissionCodes: string[]
): Promise<{ user_id: string; role_id: string; permission_codes: string[] }> {
  return adminFetch(token, `/admin/users/${userId}/permissions`, {
    method: "PUT", body: JSON.stringify({ tenant_id: tenantId, permission_codes: permissionCodes }),
  });
}

export async function fetchAdminAuditLog(
  token: string, tenantId?: string, userId?: string
): Promise<AdminAuditEntry[]> {
  const params = new URLSearchParams();
  if (tenantId) params.set("tenant_id", tenantId);
  if (userId) params.set("user_id", userId);
  return adminFetch(token, `/admin/audit-log${params.toString() ? `?${params}` : ""}`);
}

export async function sendChatMessage(
  token: string,
  conversationId: string | null,
  message: string
): Promise<ChatResponse> {
  const res = await fetch(`${API_BASE}/chat/message`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ conversation_id: conversationId, message }),
  });
  return handle<ChatResponse>(res);
}

export async function fetchConversations(token: string): Promise<ConversationSummary[]> {
  const res = await fetch(`${API_BASE}/chat/conversations`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<ConversationSummary[]>(res);
}

export async function fetchConversationMessages(token: string, conversationId: string): Promise<StoredMessage[]> {
  const res = await fetch(`${API_BASE}/chat/conversations/${conversationId}/messages`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<StoredMessage[]>(res);
}

export async function deleteConversation(token: string, conversationId: string): Promise<void> {
  await fetch(`${API_BASE}/chat/conversations/${conversationId}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
}

export async function fetchUseCases(token: string): Promise<UseCase[]> {
  const res = await fetch(`${API_BASE}/use-cases`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<UseCase[]>(res);
}

export async function createUseCase(
  token: string,
  data: { title: string; description: string; category: string; sample_question: string; generated_sql?: string | null }
): Promise<{ id: string }> {
  const res = await fetch(`${API_BASE}/use-cases`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(data),
  });
  return handle(res);
}

export async function updateUseCase(
  token: string,
  id: string,
  data: { title: string; description: string; category: string; sample_question: string; generated_sql?: string | null }
): Promise<{ id: string }> {
  const res = await fetch(`${API_BASE}/use-cases/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(data),
  });
  return handle(res);
}

// Re-runs a use case's ALREADY-SAVED SQL directly — no LLM call. Only
// works once a use case actually has cached SQL (has_cached_query), set
// the one time it was previewed while being created.
export async function runUseCase(
  token: string, id: string
): Promise<{ sql: string; columns: string[]; rows: any[][] }> {
  const res = await fetch(`${API_BASE}/use-cases/${id}/run`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle(res);
}

export async function deleteUseCase(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/use-cases/${id}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  await handle(res);
}

export async function fetchPinnedItems(token: string): Promise<PinnedItem[]> {
  const res = await fetch(`${API_BASE}/dashboard/items`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<PinnedItem[]>(res);
}

export async function pinItem(
  token: string,
  source: string,
  itemType: "insight" | "table" | "chart",
  title: string,
  payload: any
): Promise<{ id: string }> {
  const res = await fetch(`${API_BASE}/dashboard/items`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ source, item_type: itemType, title, payload }),
  });
  return handle(res);
}

export async function deletePinnedItem(token: string, id: string): Promise<void> {
  await fetch(`${API_BASE}/dashboard/items/${id}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
}

export interface DashboardShare {
  id: string;
  shared_with_user_id: string;
  display_name: string;
  email: string;
}

export async function fetchMyDashboardShares(token: string): Promise<DashboardShare[]> {
  const res = await fetch(`${API_BASE}/dashboard/shares`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle(res);
}

export async function shareDashboard(token: string, email: string): Promise<{ shared_with: string }> {
  const res = await fetch(`${API_BASE}/dashboard/shares`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ email }),
  });
  return handle(res);
}

export async function unshareDashboard(token: string, shareId: string): Promise<void> {
  await fetch(`${API_BASE}/dashboard/shares/${shareId}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
}

// ── Per-user Credentials (Profile → Credentials) ────────────────────────
// See CREDENTIAL_MANAGEMENT_DESIGN.md. Raw secrets (PAT, LLM API key) are
// only ever sent TO the backend, never received back — every response
// here only ever contains masked strings like "dapi••••••••••••ABC3" or
// opaque status flags, never the real value.

export interface CredentialsInput {
  databricks_host?: string;
  databricks_warehouse_id?: string;
  databricks_genie_space_id?: string;
  databricks_catalog?: string;
  databricks_schema?: string;
  databricks_pat?: string;
  llm_provider?: string;
  llm_api_key?: string;
}

export interface ValidateResult {
  databricks: { ok: boolean; detail: string } | null;
  llm: { ok: boolean; detail: string } | null;
}

export interface CredentialsStatus {
  configured: boolean;
  persisted: boolean;
  databricks_host: string | null;
  databricks_warehouse_id: string | null;
  databricks_genie_space_id: string | null;
  databricks_catalog: string | null;
  databricks_schema: string | null;
  databricks_pat_masked: string | null;
  llm_provider: string | null;
  llm_api_key_masked: string | null;
  last_validated_at: string | null;
  last_validation_ok: boolean | null;
}

export async function validateCredentials(token: string, data: CredentialsInput): Promise<ValidateResult> {
  const res = await fetch(`${API_BASE}/credentials/validate`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(data),
  });
  return handle<ValidateResult>(res);
}

export async function fetchCredentialsStatus(token: string): Promise<CredentialsStatus> {
  const res = await fetch(`${API_BASE}/credentials/status`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<CredentialsStatus>(res);
}

export async function saveCredentials(
  token: string,
  data: CredentialsInput,
  persist: boolean
): Promise<CredentialsStatus> {
  const res = await fetch(`${API_BASE}/credentials/`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ ...data, persist }),
  });
  return handle<CredentialsStatus>(res);
}

export async function testStoredCredentials(token: string): Promise<ValidateResult> {
  const res = await fetch(`${API_BASE}/credentials/test`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<ValidateResult>(res);
}

export async function rotatePat(token: string, newPat: string): Promise<CredentialsStatus> {
  const res = await fetch(`${API_BASE}/credentials/rotate-pat?new_pat=${encodeURIComponent(newPat)}`, {
    method: "PUT",
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<CredentialsStatus>(res);
}

export async function rotateLlmKey(token: string, newKey: string): Promise<CredentialsStatus> {
  const res = await fetch(`${API_BASE}/credentials/rotate-llm-key?new_key=${encodeURIComponent(newKey)}`, {
    method: "PUT",
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<CredentialsStatus>(res);
}

export async function deleteCredentials(token: string): Promise<void> {
  await fetch(`${API_BASE}/credentials/`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
}

// ── Genie dynamic configuration (query parameter dropdowns, question
// template, suggested questions) — set per tenant/user by a Platform
// Super Admin, never hardcoded here. See backend/app/routers/databricks.py
// ── /data/genie-config for how personal-vs-tenant-default is resolved.
export interface GenieField {
  field_name: string;
  options: string[];
}

export interface GenieConfig {
  fields: GenieField[];
  template: string | null;
  suggested_questions: string[];
}

export async function fetchGenieConfig(token: string): Promise<GenieConfig> {
  const res = await fetch(`${API_BASE}/data/genie-config`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return handle<GenieConfig>(res);
}

