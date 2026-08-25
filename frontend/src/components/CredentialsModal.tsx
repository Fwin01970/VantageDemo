import { useEffect, useState } from "react";
import {
  CredentialsInput, CredentialsStatus, ValidateResult,
  validateCredentials, fetchCredentialsStatus, saveCredentials,
  testStoredCredentials, rotatePat, rotateLlmKey, deleteCredentials,
} from "../lib/api";
import ConfirmDialog from "./ConfirmDialog";

interface Props {
  token: string;
  onClose: () => void;
}

type Stage = "loading" | "view" | "form" | "save-prompt" | "rotate-pat" | "rotate-key";

const LLM_PROVIDERS = [
  { value: "gemini", label: "Google Gemini" },
  { value: "openai", label: "OpenAI" },
  { value: "anthropic", label: "Anthropic" },
];

export default function CredentialsModal({ token, onClose }: Props) {
  const [stage, setStage] = useState<Stage>("loading");
  const [status, setStatus] = useState<CredentialsStatus | null>(null);
  const [form, setForm] = useState<CredentialsInput>({ llm_provider: "gemini" });
  const [validateResult, setValidateResult] = useState<ValidateResult | null>(null);
  const [testResult, setTestResult] = useState<ValidateResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rotateValue, setRotateValue] = useState("");
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  useEffect(() => {
    fetchCredentialsStatus(token)
      .then((s) => {
        setStatus(s);
        setStage(s.configured ? "view" : "form");
      })
      .catch(() => setStage("form"));
  }, [token]);

  async function handleValidate() {
    setBusy(true);
    setError(null);
    try {
      const result = await validateCredentials(token, form);
      setValidateResult(result);
      const dbOk = !result.databricks || result.databricks.ok;
      const llmOk = !result.llm || result.llm.ok;
      if (dbOk && llmOk) setStage("save-prompt");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Validation failed.");
    } finally {
      setBusy(false);
    }
  }

  async function handleSave(persist: boolean) {
    setBusy(true);
    setError(null);
    try {
      const s = await saveCredentials(token, form, persist);
      setStatus(s);
      setStage("view");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Save failed.");
    } finally {
      setBusy(false);
    }
  }

  async function handleTest() {
    setBusy(true);
    setError(null);
    setTestResult(null);
    try {
      setTestResult(await testStoredCredentials(token));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Test failed.");
    } finally {
      setBusy(false);
    }
  }

  async function handleRotate(kind: "pat" | "key") {
    if (!rotateValue.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const s = kind === "pat" ? await rotatePat(token, rotateValue) : await rotateLlmKey(token, rotateValue);
      setStatus(s);
      setRotateValue("");
      setStage("view");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Rotation failed.");
    } finally {
      setBusy(false);
    }
  }

  function handleDeleteClick() {
    setShowDeleteConfirm(true);
  }

  async function handleDeleteConfirmed() {
    setShowDeleteConfirm(false);
    setBusy(true);
    try {
      await deleteCredentials(token);
      setStatus(null);
      setForm({ llm_provider: "gemini" });
      setStage("form");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div style={styles.header}>
          <div style={styles.title}>Your Databricks &amp; AI credentials</div>
          <button style={styles.closeBtn} onClick={onClose} aria-label="Close">×</button>
        </div>
        <div style={styles.subtitle}>
          Optional — without these, you use your company's shared connection. Configuring your own lets
          your queries run under your own Databricks identity instead.
        </div>

        {error && <div style={styles.errorBox}>{error}</div>}

        {stage === "loading" && <div style={styles.loading}>Loading…</div>}

        {stage === "view" && status && (
          <div>
            <div style={styles.statusBadge}>
              {status.persisted ? "🔒 Saved securely" : "⏱ Session only — cleared when you log out"}
            </div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>Databricks host</span><span>{status.databricks_host || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>Warehouse ID</span><span>{status.databricks_warehouse_id || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>Genie Space ID</span><span>{status.databricks_genie_space_id || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>Catalog / Schema</span><span>{status.databricks_catalog || "—"} / {status.databricks_schema || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>Databricks PAT</span><span style={styles.masked}>{status.databricks_pat_masked || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>LLM provider</span><span>{status.llm_provider || "—"}</span></div>
            <div style={styles.fieldRow}><span style={styles.fieldLabel}>LLM API key</span><span style={styles.masked}>{status.llm_api_key_masked || "—"}</span></div>
            {status.last_validated_at && (
              <div style={styles.fieldRow}>
                <span style={styles.fieldLabel}>Last validated</span>
                <span>{new Date(status.last_validated_at).toLocaleString()} — {status.last_validation_ok ? "✅ OK" : "⚠ Failed"}</span>
              </div>
            )}

            {testResult && (
              <div style={styles.testResultBox}>
                {testResult.databricks && <div>Databricks: {testResult.databricks.ok ? "✅" : "❌"} {testResult.databricks.detail}</div>}
                {testResult.llm && <div>LLM: {testResult.llm.ok ? "✅" : "❌"} {testResult.llm.detail}</div>}
              </div>
            )}

            <div style={styles.actionRow}>
              <button style={styles.secondaryBtn} onClick={handleTest} disabled={busy}>Test connection</button>
              <button style={styles.secondaryBtn} onClick={() => setStage("rotate-pat")} disabled={busy}>Rotate PAT</button>
              <button style={styles.secondaryBtn} onClick={() => setStage("rotate-key")} disabled={busy}>Rotate LLM key</button>
              <button style={styles.secondaryBtn} onClick={() => setStage("form")} disabled={busy}>Edit / reconfigure</button>
              <button style={styles.dangerBtn} onClick={handleDeleteClick} disabled={busy}>Delete</button>
            </div>
            <div style={styles.continueRow}>
              <button style={styles.primaryBtn} onClick={onClose}>Continue</button>
            </div>
          </div>
        )}

        {(stage === "rotate-pat" || stage === "rotate-key") && (
          <div>
            <label style={styles.label}>{stage === "rotate-pat" ? "New Databricks PAT" : "New LLM API key"}</label>
            <input
              style={styles.input}
              type="password"
              value={rotateValue}
              onChange={(e) => setRotateValue(e.target.value)}
              placeholder={stage === "rotate-pat" ? "dapi..." : "sk-..."}
            />
            <div style={styles.actionRow}>
              <button style={styles.secondaryBtn} onClick={() => { setStage("view"); setRotateValue(""); }}>Cancel</button>
              <button style={styles.primaryBtn} onClick={() => handleRotate(stage === "rotate-pat" ? "pat" : "key")} disabled={busy || !rotateValue.trim()}>
                {busy ? "Rotating…" : "Rotate"}
              </button>
            </div>
          </div>
        )}

        {stage === "form" && (
          <div>
            <label style={styles.label}>Databricks workspace host</label>
            <input style={styles.input} placeholder="dbc-xxxxxxx-xxxx.cloud.databricks.com"
              value={form.databricks_host || ""} onChange={(e) => setForm({ ...form, databricks_host: e.target.value })} />

            <label style={styles.label}>Warehouse ID</label>
            <input style={styles.input} value={form.databricks_warehouse_id || ""}
              onChange={(e) => setForm({ ...form, databricks_warehouse_id: e.target.value })} />

            <label style={styles.label}>Genie Space ID <span style={styles.optionalTag}>optional</span></label>
            <input style={styles.input} value={form.databricks_genie_space_id || ""}
              onChange={(e) => setForm({ ...form, databricks_genie_space_id: e.target.value })} />

            <div style={styles.twoCol}>
              <div>
                <label style={styles.label}>Catalog <span style={styles.optionalTag}>optional</span></label>
                <input style={styles.input} value={form.databricks_catalog || ""}
                  onChange={(e) => setForm({ ...form, databricks_catalog: e.target.value })} />
              </div>
              <div>
                <label style={styles.label}>Schema <span style={styles.optionalTag}>optional</span></label>
                <input style={styles.input} value={form.databricks_schema || ""}
                  onChange={(e) => setForm({ ...form, databricks_schema: e.target.value })} />
              </div>
            </div>

            <label style={styles.label}>Databricks PAT</label>
            <input style={styles.input} type="password" placeholder="dapi..."
              value={form.databricks_pat || ""} onChange={(e) => setForm({ ...form, databricks_pat: e.target.value })} />

            <label style={styles.label}>LLM provider</label>
            <select style={styles.input} value={form.llm_provider} onChange={(e) => setForm({ ...form, llm_provider: e.target.value })}>
              {LLM_PROVIDERS.map((p) => <option key={p.value} value={p.value}>{p.label}</option>)}
            </select>

            <label style={styles.label}>LLM API key</label>
            <input style={styles.input} type="password" placeholder="sk-..."
              value={form.llm_api_key || ""} onChange={(e) => setForm({ ...form, llm_api_key: e.target.value })} />

            {validateResult && (
              <div style={styles.testResultBox}>
                {validateResult.databricks && <div>Databricks: {validateResult.databricks.ok ? "✅" : "❌"} {validateResult.databricks.detail}</div>}
                {validateResult.llm && <div>LLM: {validateResult.llm.ok ? "✅" : "❌"} {validateResult.llm.detail}</div>}
              </div>
            )}

            <div style={styles.actionRow}>
              {status && <button style={styles.secondaryBtn} onClick={() => setStage("view")} disabled={busy}>Cancel</button>}
              <button style={styles.primaryBtn} onClick={handleValidate} disabled={busy}>
                {busy ? "Testing…" : "Test & Continue"}
              </button>
            </div>
          </div>
        )}

        {stage === "save-prompt" && (
          <div style={styles.savePrompt}>
            <div style={styles.savePromptTitle}>Would you like to securely save these credentials for future use?</div>
            <div style={styles.savePromptBody}>
              <strong>Save Securely</strong> encrypts and stores them so you won't need to re-enter them next time you
              log in. <strong>Not Now</strong> keeps them only for this session — you'll need to re-enter them next time.
            </div>
            <div style={styles.actionRow}>
              <button style={styles.secondaryBtn} onClick={() => handleSave(false)} disabled={busy}>Not Now</button>
              <button style={styles.primaryBtn} onClick={() => handleSave(true)} disabled={busy}>
                {busy ? "Saving…" : "Save Securely"}
              </button>
            </div>
          </div>
        )}
      </div>

      {showDeleteConfirm && (
        <ConfirmDialog
          title="Remove your personal credentials?"
          message="You'll fall back to your company's shared connection. This can't be undone — you'd need to re-enter everything to set it up again."
          confirmLabel="Remove"
          danger
          onConfirm={handleDeleteConfirmed}
          onCancel={() => setShowDeleteConfirm(false)}
        />
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: { position: "fixed", inset: 0, background: "rgba(18,22,28,0.45)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100 },
  panel: { width: "min(560px, 92vw)", maxHeight: "85vh", overflowY: "auto", background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 12, padding: 24, boxShadow: "var(--shadow)" },
  header: { display: "flex", justifyContent: "space-between", alignItems: "flex-start" },
  title: { fontWeight: 700, fontSize: 16, color: "var(--ink)" },
  closeBtn: { background: "none", border: "none", fontSize: 20, cursor: "pointer", color: "var(--ink-soft)", lineHeight: 1 },
  subtitle: { fontSize: 12.5, color: "var(--ink-soft)", marginTop: 4, marginBottom: 18, lineHeight: 1.5 },
  loading: { fontSize: 13, color: "var(--ink-soft)", padding: "20px 0" },
  errorBox: { background: "#fdecea", color: "#a33", border: "1px solid #f3c6c2", borderRadius: 8, padding: "8px 12px", fontSize: 12.5, marginBottom: 14 },
  statusBadge: { fontSize: 12, fontWeight: 600, marginBottom: 14, color: "var(--ink)" },
  fieldRow: { display: "flex", justifyContent: "space-between", padding: "7px 0", borderBottom: "1px solid var(--line)", fontSize: 13 },
  fieldLabel: { color: "var(--ink-soft)" },
  masked: { fontFamily: "monospace", letterSpacing: 0.5 },
  testResultBox: { background: "var(--paper)", border: "1px solid var(--line)", borderRadius: 8, padding: "10px 12px", fontSize: 12.5, marginTop: 12, lineHeight: 1.6 },
  actionRow: { display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 18, flexWrap: "wrap" },
  continueRow: { display: "flex", justifyContent: "flex-end", marginTop: 16, paddingTop: 16, borderTop: "1px solid var(--line)" },
  label: { display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", marginTop: 14, marginBottom: 5 },
  optionalTag: { fontWeight: 400, fontStyle: "italic", color: "var(--ink-soft)" },
  input: { width: "100%", padding: "8px 10px", borderRadius: 8, border: "1px solid var(--line)", fontSize: 13, background: "var(--surface)", color: "var(--ink)" },
  twoCol: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 },
  primaryBtn: { background: "var(--primary)", color: "white", border: "none", borderRadius: 8, padding: "8px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  secondaryBtn: { background: "none", border: "1px solid var(--line)", borderRadius: 8, padding: "8px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer", color: "var(--ink)" },
  dangerBtn: { background: "none", border: "1px solid var(--danger)", color: "var(--danger)", borderRadius: 8, padding: "8px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  savePrompt: { padding: "8px 0" },
  savePromptTitle: { fontWeight: 700, fontSize: 14.5, marginBottom: 10, color: "var(--ink)" },
  savePromptBody: { fontSize: 12.5, color: "var(--ink-soft)", lineHeight: 1.6 },
};
