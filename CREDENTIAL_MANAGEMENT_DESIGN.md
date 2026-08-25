# Per-User Credential Management — Design Document

**Status:** Designed and implemented (backend + frontend). Encryption round-trip and masking logic verified in this environment; Azure Key Vault integration is a documented, not-yet-wired seam (no Azure environment available here — see "Secret Storage Architecture" below for exactly what that means).

**Where this fits in the app:** a new item in the user profile dropdown ("Credentials"), opening a settings panel — not a new top-level nav tab, per the request.

---

## 0. Why this matters (and how it relates to what's already built)

Today, Databricks access is **per-tenant**: one shared PAT (`data_source_connections.secret_ref` → an env var) is used by every user at a company. This was flagged earlier as a real gap — from Databricks' point of view, every user of a tenant is the same identity, so per-user Unity Catalog permissions can't actually apply.

This feature is the fix for that: **each user can supply their own Databricks credentials** (and their own LLM API key, useful for orgs that want to bill/rate-limit per user rather than per company). Critically, this is designed to be **backward compatible** — a user who hasn't set up personal credentials keeps using the tenant-wide shared PAT exactly as before. Nothing breaks for tenants that never touch this feature.

---

## 1. Frontend Workflow Design

### 1.1 First-time entry point
On login, if the user has **no** credentials configured (checked via `GET /credentials/status`) and the account has `data:query` permission, a **non-blocking banner** (not a hard modal — per the SaaS-usability principle of not forcing setup before someone has even seen the product) appears once, inviting them to configure their own connection, with a "Maybe later" dismiss. This deliberately does *not* force it, since tenant-wide credentials mean the app is still fully usable without it.

### 1.2 Credentials setup form
Reachable via **Profile dropdown → Credentials**, before "Sign out." Fields:
- Databricks Workspace Host (e.g. `dbc-xxxx.cloud.databricks.com`)
- Databricks Warehouse ID
- Databricks Genie Space ID *(optional — only needed if they use the Genie tab)*
- Databricks Catalog / Schema *(optional — needed for the Ask AI direct-SQL path)*
- Databricks PAT
- LLM Provider (dropdown: OpenAI / Azure OpenAI / Anthropic / Gemini)
- LLM API Key

### 1.3 Validate → Save-prompt flow
1. User clicks **"Test & Continue."**
2. Frontend calls `POST /credentials/validate` with the raw values — **this call does not persist anything.**
3. Backend actually opens a connection to Databricks (`SELECT 1`) and pings the chosen LLM provider (a minimal `generate()` call, same pattern already used elsewhere in this app), and returns pass/fail **per credential**, not just one blob (so the user knows exactly which one is wrong, without ever being shown their own secret back).
4. On success, a modal appears:
   > **"Would you like to securely save these credentials for future use?"**
   > `[ Save Securely ]` `[ Not Now ]`
5. **Save Securely** → `POST /credentials` with `persist: true`. Secrets go to the secret store (see §4); non-sensitive metadata goes to Postgres.
6. **Not Now** → `POST /credentials` with `persist: false`. Secrets live **only** in an in-memory, TTL-bound session cache, server-side, tied to this login's token — never written to any table, never touch localStorage/sessionStorage in the browser (see §7 for why that matters).

### 1.4 Settings → Credentials page
Shows current state (masked), with actions:
- **View** — masked values only (`dapi••••••••••••ABC3`, `sk-••••••••••••XYZ9`) — the raw secret is never sent back to the browser after initial entry, full stop.
- **Update / Rotate PAT** — new secret in, old one invalidated in the secret store immediately.
- **Rotate LLM API Key** — same pattern.
- **Test connection** — re-runs the same validation as §1.3 without needing to re-enter secrets (backend already holds them).
- **Delete** — removes both the metadata row and the secret store entry; falls back to tenant-shared credentials afterward, doesn't break the user's access.

---

## 2. Backend Architecture

```
┌─────────────┐      ┌──────────────────────┐      ┌────────────────────┐
│   Frontend   │─────▶│  /credentials router  │─────▶│   SecretStore (abstract) │
└─────────────┘ HTTPS└──────────────────────┘      └─────────┬──────────┘
                              │                                │
                              ▼                     ┌──────────┴───────────┐
                     ┌─────────────────┐             │                      │
                     │ user_credentials │      LocalEncryptedSecretStore   AzureKeyVaultSecretStore
                     │  (Postgres, RLS) │        (implemented, default)      (interface only —
                     │ metadata only —  │                                    not wired to a real
                     │ NEVER the secret │                                    vault in this env)
                     └─────────────────┘
                              │
                              ▼
                  data_source_resolver.py
            (checks user_credentials FIRST,
             falls back to tenant-wide PAT)
```

Key architectural decision: **`SecretStore` is an interface**, not a concrete Key Vault call sprinkled through the code. `chat.py`, `databricks.py`, and everything downstream never know or care whether a secret came from Azure Key Vault or a local encrypted column — they just call `get_databricks_client_for_user(...)`. This means swapping in real Azure Key Vault later is a one-file change (`secret_store.py`), not a rewrite.

---

## 3. Database Schema

One new table, `user_credentials` — **metadata only, never the raw secret**:

```sql
CREATE TABLE user_credentials (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    databricks_host         TEXT,
    databricks_warehouse_id TEXT,
    databricks_genie_space_id TEXT,
    databricks_catalog       TEXT,
    databricks_schema        TEXT,
    databricks_pat_secret_ref  TEXT,   -- opaque handle INTO the secret store, e.g.
                                        -- "azure-kv:ryze-user-<uuid>-databricks-pat"
                                        -- or "local:<uuid>" for the local store.
                                        -- Never the PAT itself.

    llm_provider             TEXT,      -- 'openai' | 'azure_openai' | 'anthropic' | 'gemini'
    llm_api_key_secret_ref   TEXT,      -- same pattern as above

    is_session_only         BOOLEAN NOT NULL DEFAULT false,  -- true = "Not Now" was chosen;
                                                              -- row shouldn't normally exist for
                                                              -- this case (see §5), kept for
                                                              -- audit-trail completeness only
    last_validated_at        TIMESTAMPTZ,
    last_validation_ok       BOOLEAN,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id)   -- one credential set per user, matching the "profile settings" framing
);

ALTER TABLE user_credentials ENABLE ROW LEVEL SECURITY;

-- Ownership check, not just tenant check: a user can only ever see their OWN row,
-- not their whole tenant's — this is deliberately stricter than every other
-- RLS policy in this app, because credentials are personal, not company-shared.
CREATE POLICY user_owns_credentials ON user_credentials
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND user_id = current_setting('app.current_user_id', true)::uuid
    );
```

Note the RLS policy needs a **new** session variable, `app.current_user_id`, alongside the existing `app.current_tenant_id` — every other table in this app is tenant-scoped, this is the first one that's also user-scoped. `get_db()` needs to set both per-request.

---

## 4. Secret Storage Architecture

### 4.1 The interface (what every environment implements)

```python
class SecretStore(ABC):
    def store(self, ref_prefix: str, plaintext: str) -> str: ...   # returns opaque secret_ref
    def retrieve(self, secret_ref: str) -> str: ...
    def delete(self, secret_ref: str) -> None: ...
    def rotate(self, secret_ref: str, new_plaintext: str) -> str: ...  # old ref invalidated
```

### 4.2 `LocalEncryptedSecretStore` — implemented and verified here

For this environment (and any deployment without Azure), secrets are encrypted with **Fernet** (AES-128-CBC + HMAC, from the `cryptography` library) using a master key from `SECRET_STORE_MASTER_KEY` (an env var — **never committed, never in the DB**), and stored in a dedicated `local_secrets` table (separate from `user_credentials`, so even a full dump of `user_credentials` reveals nothing but opaque references).

I generated a master key and ran a real encrypt → store → retrieve → decrypt round trip in this sandbox to confirm the implementation is actually correct, not just "looks right" — see the verification output later in this conversation.

### 4.3 `AzureKeyVaultSecretStore` — interface defined, **not wired to a real vault here**

Being direct about this: I don't have an Azure subscription or Key Vault instance in this sandbox, so I can't verify real calls against `azure-keyvault-secrets`. What I've built is:
- The exact method signatures the rest of the app calls, matching `SecretStore`
- Correct use of `DefaultAzureCredential` (works with Managed Identity in Azure, or `az login` locally — no secrets-to-access-secrets problem)
- Clear `NotImplementedError` messages if selected without the SDK installed / configured, rather than silently falling back to something insecure

**This should be treated as a well-reasoned starting point, not a tested integration**, until someone with real Azure access runs it once, the same honesty standard applied to the Databricks/LLM provider code earlier in this project.

### 4.4 Session-only path ("Not Now")
No `user_credentials` row, no secret store entry, no database write of any kind. Secrets live in a process-local dict (`credential_session_cache.py`), keyed by a hash of the JWT, with a TTL matching the token's own expiry. Restarting the backend, logging out, or the token expiring all correctly wipe it — there's nothing to "leak" because nothing persists past the process's memory.

**Scalability note (§9 expands on this):** an in-process dict only works for a single backend instance. The moment this runs behind a load balancer with multiple instances, session-only credentials need to move to Redis (or similar) so any instance can serve the request — noted as a required change before horizontal scaling, not a hidden gap.

---

## 5. API Design

| Method & Path | Purpose | Auth |
|---|---|---|
| `GET /credentials/status` | Does this user have credentials configured (persisted or session)? Masked summary only. | own row |
| `POST /credentials/validate` | Test connectivity — **never persists** | any authenticated user |
| `POST /credentials` | Save — `persist: bool` decides DB+secret-store vs. session-only | own row |
| `PUT /credentials/rotate-pat` | Rotate just the Databricks PAT | own row |
| `PUT /credentials/rotate-llm-key` | Rotate just the LLM API key | own row |
| `POST /credentials/test` | Re-validate the currently stored/session credentials | own row |
| `DELETE /credentials` | Remove persisted credentials (falls back to tenant-wide) | own row |

Every response is masked server-side before serialization — there is no code path where a raw secret is included in a JSON response, ever, including error responses (validation errors report *which field* failed, never echo the value).

---

## 6. Session Management Flow

```
Login (existing flow, unchanged)
   │
   ▼
JWT issued, as today
   │
   ▼
GET /credentials/status
   │
   ├── persisted row exists ──▶ use it (decrypt on demand, per-request, never cached in plaintext)
   │
   ├── session-only entry exists for this token ──▶ use it
   │
   └── neither ──▶ fall back to tenant-wide data_source_connections (today's behavior)

Logout / token expiry
   │
   ▼
Session-only cache entry deleted immediately (not just left to TTL) —
persisted credentials are untouched (that's the whole point of persisting them).
```

---

## 7. Security Considerations (mapped directly to the requirements given)

| Requirement | How it's met |
|---|---|
| Never hardcode secrets | `SECRET_STORE_MASTER_KEY` is env-only; `.env.example` documents the variable name with a placeholder, never a real value |
| Never store secrets in localStorage/sessionStorage | Confirmed — the frontend never receives a raw secret after initial entry; only masked strings and opaque IDs cross the network after that point |
| Never expose secrets in logs/responses/errors | `logger.info`/`logger.warning` calls in the new router only ever log the masked form or the secret_ref, never the plaintext — audited line-by-line in the code below |
| Mask sensitive values in UI | `mask_secret()` helper, verified below | 
| HTTPS | Enforced at the deployment layer (reverse proxy/load balancer), same as every other endpoint — noted as an infra requirement, not something app code can itself guarantee |
| Encrypt secrets before persistence | Fernet, verified round-trip |
| RBAC — own credentials only | New RLS policy checks `user_id`, not just `tenant_id` — stricter than the rest of the app |
| Rotation without downtime | `rotate()` writes the new secret and only updates `secret_ref` after a successful write — old secret is deleted only after the new one is confirmed stored, so a crash mid-rotation never leaves the user with *no* working credential |
| Audit logging | Every create/update/rotate/delete/validate call logs via the existing `log_event()` — action name, timestamp, user — **never the secret value or even the masked form**, since even a masked value is metadata that doesn't need to sit in an audit table |

---

## 8. Error Handling Scenarios

| Scenario | Behavior |
|---|---|
| Databricks host unreachable | `validate` returns `{"databricks": {"ok": false, "detail": "..."}}` — specific, no stack trace, no internal path info |
| PAT valid but lacks warehouse access | Distinguished from "host unreachable" — Databricks' own 403 is surfaced as a clear "token doesn't have access to this warehouse" message |
| LLM API key invalid | Same per-credential granularity — user isn't left guessing whether it was Databricks or the LLM key that failed |
| Secret store unreachable at save time (e.g. Key Vault down) | Save fails cleanly, nothing partially written — either both the metadata row and the secret exist, or neither does (no orphaned metadata pointing at a secret that was never actually stored) |
| Session-only credential's token expires mid-session | Next request that needs it gets a clear "please reconnect your credentials" rather than a confusing downstream Databricks auth error |
| Rotation fails partway | Old secret_ref stays valid until the new secret is confirmed written — see §7 |

---

## 9. Future Scalability Recommendations

1. **Move session-only cache to Redis** before running more than one backend instance (flagged honestly in §4.4 — this is a real limitation of the current in-process implementation, not a hidden one).
2. **Wire the real Azure Key Vault implementation** and get it reviewed/tested by someone with an actual Azure subscription before this goes anywhere near production — this is the single biggest "unverified" piece in this whole design, stated plainly.
3. **Per-user rate limiting on the LLM key**, once org billing needs it — the schema already supports one API key per user, this just needs a rate-limiter reading from the same table.
4. **Secret versioning** in Key Vault (Key Vault supports this natively) so rotation history is queryable without needing our own audit table to reconstruct it.
5. Consider **short-lived Databricks OAuth tokens instead of static PATs** longer-term — same idea raised earlier in this project regarding per-user Databricks auth; this credentials feature is a good place to add that as a second supported auth mode later, without changing the surrounding architecture.
