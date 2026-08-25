import { useEffect, useMemo, useState } from "react";
import {
  fetchUseCases, createUseCase, deleteUseCase, sendChatMessage,
  UseCase, ApiError, GenieResult,
} from "../lib/api";
import ChatDataChart from "../components/ChatDataChart";
import MarkdownLite from "../components/MarkdownLite";
import ConfirmDialog from "../components/ConfirmDialog";

interface Props {
  token: string;
  canCreate: boolean;
  onSessionExpired?: () => void;
  // Feeds the same Governance lastResult state Ask AI/Genie already do,
  // so a use case's SQL/guardrails/grounding show up in the Governance
  // panel too — previously use cases only ever navigated to Ask AI and
  // relied on THAT page to populate it, which broke the moment launching
  // stopped navigating away (see RunPanel below).
  onResult?: (result: GenieResult) => void;
}

// One question run (a "Launch" or a form "Preview") and its outcome —
// shared shape so both use the exact same inline result renderer instead
// of two separate ad-hoc displays.
interface RunState {
  question: string;
  loading: boolean;
  error: string | null;
  reply: string | null;
  chartData: { columns: string[]; rows: any[][] } | null;
  blocked: boolean;
  blockedEvents: { policy: string; detail: string }[] | null;
}

const EMPTY_RUN: RunState = {
  question: "", loading: false, error: null, reply: null, chartData: null, blocked: false, blockedEvents: null,
};

export default function UseCasesPage({ token, canCreate, onSessionExpired, onResult }: Props) {
  const [cases, setCases] = useState<UseCase[] | null>(null);
  const [categoryFilter, setCategoryFilter] = useState<string>("All");
  const [showForm, setShowForm] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [deleteTargetId, setDeleteTargetId] = useState<string | null>(null);

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("");
  const [sampleQuestion, setSampleQuestion] = useState("");

  // #5 — a one-time preview of the query + result while adding a new use
  // case, so the sample question can be adjusted BEFORE it's saved as an
  // official preset, rather than only finding out it's a bad question
  // after it's already live for everyone.
  const [previewRun, setPreviewRun] = useState<RunState>(EMPTY_RUN);

  // #1 — launching a use case runs it and shows the result on THIS page
  // (below the grid) instead of navigating to Ask AI. One shared slot
  // rather than per-card state, since only one launch is ever "current."
  const [launchedTitle, setLaunchedTitle] = useState<string | null>(null);
  const [launchRun, setLaunchRun] = useState<RunState>(EMPTY_RUN);

  function load() {
    fetchUseCases(token).then(setCases).catch(() => setCases([]));
  }

  useEffect(load, [token]);

  const categories = useMemo(() => {
    const set = new Set((cases ?? []).map((c) => c.category));
    return ["All", ...Array.from(set)];
  }, [cases]);

  const filtered = (cases ?? []).filter((c) => categoryFilter === "All" || c.category === categoryFilter);

  // Shared runner for both Launch and Preview — identical backend call,
  // identical result shape, only the target state setter differs.
  async function runQuestion(question: string, setState: (r: RunState) => void) {
    setState({ ...EMPTY_RUN, question, loading: true });
    try {
      const res = await sendChatMessage(token, null, question);
      if (res.blocked) {
        setState({
          question, loading: false, error: null, reply: null, chartData: null,
          blocked: true, blockedEvents: res.blocked_events,
        });
      } else {
        setState({
          question, loading: false, error: null, reply: res.reply,
          chartData: res.chart_data, blocked: false, blockedEvents: null,
        });
      }
      onResult?.({
        sql: res.sql,
        summary: res.blocked ? null : res.reply,
        columns: res.chart_data?.columns ?? [],
        rows: res.chart_data?.rows ?? [],
        row_count: res.chart_data?.rows?.length ?? 0,
        conversation_id: res.conversation_id || "",
        message_id: "",
        guardrails: {
          input_events: res.blocked ? (res.blocked_events ?? []) : res.guardrail_input_events,
          llm_check: { ran: !res.blocked, provider_used: res.provider_used },
          grounding: res.grounding,
        },
      });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        onSessionExpired?.();
      }
      setState({
        ...EMPTY_RUN, question,
        error: e instanceof Error ? e.message : "Something went wrong running this question.",
      });
    }
  }

  function handleLaunch(c: UseCase) {
    setLaunchedTitle(c.title);
    runQuestion(c.sample_question, setLaunchRun);
  }

  function handlePreview() {
    if (!sampleQuestion.trim()) {
      setFormError("Enter a sample question first.");
      return;
    }
    setFormError(null);
    runQuestion(sampleQuestion, setPreviewRun);
  }

  async function handleCreate() {
    if (!title.trim() || !description.trim() || !category.trim() || !sampleQuestion.trim()) {
      setFormError("All fields are required.");
      return;
    }
    setSaving(true);
    setFormError(null);
    try {
      await createUseCase(token, { title, description, category, sample_question: sampleQuestion });
      setTitle(""); setDescription(""); setCategory(""); setSampleQuestion("");
      setPreviewRun(EMPTY_RUN);
      setShowForm(false);
      load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e.message : "Something went wrong.");
    } finally {
      setSaving(false);
    }
  }

  async function confirmDelete() {
    if (!deleteTargetId) return;
    try {
      await deleteUseCase(token, deleteTargetId);
      setCases((prev) => (prev ? prev.filter((c) => c.id !== deleteTargetId) : prev));
    } catch {
      /* non-critical — list stays as-is, user can retry */
    } finally {
      setDeleteTargetId(null);
    }
  }

  return (
    <div style={styles.page}>
      <div style={styles.heading}>
        <div>
          <h1 style={styles.h1}>Preset use cases</h1>
          <p style={styles.sub}>Configured per company — this list is specific to your industry, not hardcoded.</p>
        </div>
        <div style={styles.headingActions}>
          <select style={styles.filterSelect} value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
            {categories.map((c) => <option key={c}>{c}</option>)}
          </select>
          {canCreate && (
            <button style={styles.createBtn} onClick={() => setShowForm((s) => !s)}>
              + Create use case
            </button>
          )}
        </div>
      </div>

      {showForm && (
        <div style={styles.formCard}>
          <div style={styles.formGrid}>
            <div>
              <label style={styles.label}>Title</label>
              <input style={styles.input} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Renewal risk" />
            </div>
            <div>
              <label style={styles.label}>Category</label>
              <input style={styles.input} value={category} onChange={(e) => setCategory(e.target.value)} placeholder="e.g. Claims" />
            </div>
          </div>
          <label style={styles.label}>Description</label>
          <input style={styles.input} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="One line describing what this analyzes" />
          <label style={styles.label}>Sample question (what gets asked when someone clicks Launch)</label>
          <div style={styles.previewRow}>
            <input
              style={{ ...styles.input, flex: 1 }}
              value={sampleQuestion}
              onChange={(e) => setSampleQuestion(e.target.value)}
              placeholder="e.g. Show renewal rates by product this quarter"
            />
            <button style={styles.previewBtn} onClick={handlePreview} disabled={previewRun.loading}>
              {previewRun.loading ? "Running…" : "▶ Preview"}
            </button>
          </div>
          <p style={styles.previewHint}>
            Preview runs the question once so you can see the actual query result before saving —
            adjust the wording and preview again as many times as you like.
          </p>

          {(previewRun.reply || previewRun.blocked || previewRun.error) && (
            <RunResultPanel run={previewRun} />
          )}

          {formError && <div style={styles.formError}>{formError}</div>}
          <div style={styles.formActions}>
            <button style={styles.cancelBtn} onClick={() => { setShowForm(false); setPreviewRun(EMPTY_RUN); }}>Cancel</button>
            <button style={styles.saveBtn} onClick={handleCreate} disabled={saving}>{saving ? "Saving…" : "Save use case"}</button>
          </div>
        </div>
      )}

      {deleteTargetId && (
        <ConfirmDialog
          title="Delete this use case?"
          message="It will be removed from the preset list for everyone in your company. This can't be undone."
          confirmLabel="Delete"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleteTargetId(null)}
        />
      )}

      {!cases && <div style={styles.loading}>Loading…</div>}
      {cases && filtered.length === 0 && (
        <div style={styles.emptyCard}>No preset use cases match this filter yet.</div>
      )}

      <div style={styles.grid}>
        {filtered.map((c) => (
          <div key={c.id} style={styles.card}>
            {canCreate && (
              <button
                style={styles.deleteBtn}
                title="Delete this use case"
                onClick={() => setDeleteTargetId(c.id)}
              >
                ✕
              </button>
            )}
            <div style={styles.icon}>★</div>
            <h3 style={styles.title}>{c.title}</h3>
            <p style={styles.desc}>{c.description}</p>
            <div style={styles.footer}>
              <span style={styles.category}>{c.category}</span>
              <button style={styles.launchBtn} onClick={() => handleLaunch(c)} disabled={launchRun.loading}>
                {launchRun.loading && launchedTitle === c.title ? "Running…" : "Launch"}
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* #1 — result of the most recently launched use case, shown right
          here instead of navigating away to Ask AI. */}
      {launchedTitle && (launchRun.reply || launchRun.blocked || launchRun.error || launchRun.loading) && (
        <div style={styles.launchResultWrap}>
          <div style={styles.launchResultHeader}>Result — {launchedTitle}</div>
          <RunResultPanel run={launchRun} />
        </div>
      )}
    </div>
  );
}

function RunResultPanel({ run }: { run: RunState }) {
  if (run.loading) return <div style={styles.runCard}><div style={styles.runLoading}>Running "{run.question}"…</div></div>;
  if (run.error) return <div style={styles.runCard}><div style={styles.runError}>{run.error}</div></div>;
  if (run.blocked) {
    return (
      <div style={styles.runCard}>
        <div style={styles.blockedTitle}>This question was blocked by a safety guardrail</div>
        {run.blockedEvents?.map((e, i) => (
          <div key={i} style={styles.blockedEvent}>
            <span style={styles.blockedPolicy}>{e.policy}</span>
            <span>{e.detail}</span>
          </div>
        ))}
      </div>
    );
  }
  if (!run.reply) return null;
  return (
    <div style={styles.runCard}>
      <MarkdownLite text={run.reply} />
      {run.chartData && run.chartData.columns.length > 0 && (
        <ChatDataChart data={run.chartData} />
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { flex: 1, minHeight: 0, overflowY: "auto", padding: "32px 32px 60px", width: "100%" },
  heading: { display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 12, marginBottom: 20 },
  h1: { fontSize: 22, margin: "0 0 6px" },
  sub: { fontSize: 13, color: "var(--ink-soft)", margin: 0 },
  headingActions: { display: "flex", gap: 10, alignItems: "center" },
  filterSelect: { padding: "8px 12px", fontSize: 13, border: "1px solid var(--line)", borderRadius: 8, background: "var(--surface)", color: "var(--ink)" },
  createBtn: { background: "var(--primary)", color: "white", border: "none", borderRadius: 8, padding: "9px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  formCard: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 18, marginBottom: 20 },
  formGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 },
  label: { display: "block", fontSize: 12, fontWeight: 600, margin: "10px 0 5px" },
  input: { width: "100%", padding: "9px 11px", fontSize: 13.5, border: "1px solid var(--line)", borderRadius: 6, background: "var(--surface)", color: "var(--ink)" },
  previewRow: { display: "flex", gap: 8, alignItems: "stretch" },
  previewBtn: {
    flexShrink: 0, background: "var(--primary-soft)", color: "var(--primary)", border: "1px solid var(--line)",
    borderRadius: 6, padding: "0 16px", fontSize: 12.5, fontWeight: 600, cursor: "pointer",
  },
  previewHint: { fontSize: 11.5, color: "var(--ink-soft)", margin: "6px 0 0" },
  formError: { fontSize: 12.5, color: "var(--danger)", marginTop: 10 },
  formActions: { display: "flex", justifyContent: "flex-end", gap: 10, marginTop: 16 },
  cancelBtn: { background: "none", border: "1px solid var(--line)", borderRadius: 8, padding: "8px 16px", fontSize: 13, cursor: "pointer", color: "var(--ink)" },
  saveBtn: { background: "var(--primary)", color: "white", border: "none", borderRadius: 8, padding: "8px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer" },
  loading: { color: "var(--ink-soft)", fontSize: 13.5 },
  emptyCard: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 24, textAlign: "center", color: "var(--ink-soft)", fontSize: 13.5 },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 16 },
  card: { position: "relative", background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 19, display: "flex", flexDirection: "column" },
  deleteBtn: {
    position: "absolute", top: 10, right: 10, width: 22, height: 22, padding: 0,
    background: "none", border: "1px solid var(--line)", borderRadius: 6, color: "var(--ink-soft)",
    fontSize: 11, cursor: "pointer", lineHeight: 1,
  },
  icon: { width: 40, height: 40, borderRadius: 10, background: "var(--primary-soft)", color: "var(--primary)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 16, marginBottom: 12 },
  title: { fontSize: 14.5, margin: "0 0 6px", paddingRight: 20 },
  desc: { fontSize: 12, color: "var(--ink-soft)", lineHeight: 1.55, margin: 0, flex: 1 },
  footer: { marginTop: 16, display: "flex", justifyContent: "space-between", alignItems: "center" },
  category: { fontSize: 9.5, fontWeight: 700, letterSpacing: 0.5, textTransform: "uppercase", color: "var(--ink-soft)" },
  launchBtn: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 6, padding: "6px 14px", fontSize: 12, fontWeight: 600, cursor: "pointer", color: "var(--ink)" },
  launchResultWrap: { marginTop: 24 },
  launchResultHeader: { fontSize: 12, fontWeight: 700, color: "var(--ink-soft)", textTransform: "uppercase", letterSpacing: 0.4, marginBottom: 8 },
  runCard: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 18, fontSize: 13.5, lineHeight: 1.6 },
  runLoading: { color: "var(--ink-soft)" },
  runError: { color: "var(--danger)" },
  blockedTitle: { fontWeight: 700, color: "var(--danger)", marginBottom: 6, fontSize: 13 },
  blockedEvent: { fontSize: 12.5, color: "var(--ink)", display: "flex", gap: 8, marginTop: 4 },
  blockedPolicy: { fontWeight: 700, flexShrink: 0 },
};
