import { useState } from "react";
import { askGenie, GenieResult, ApiError, GuardrailEvent, pinItem, deletePinnedItem } from "../lib/api";
import ChatDataChart from "../components/ChatDataChart";
import MarkdownLite from "../components/MarkdownLite";
import { truncateTitle } from "../lib/text";

interface Props {
  token: string;
  onResult: (result: GenieResult) => void;
  sessionExpired: boolean;
  onSessionExpired: () => void;
}

const PRODUCT_LINES = ["Motor", "Property", "General Liability", "Business Interruption"];
const REGIONS = ["Midwest", "Northeast", "South", "West"];
const FOCUS_AREAS = ["Risk", "Trend", "Forecast", "Anomalies"];

export default function GeniePage({ token, onResult, sessionExpired, onSessionExpired }: Props) {
  const [question, setQuestion] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<GenieResult | null>(null);
  const [blockedEvents, setBlockedEvents] = useState<GuardrailEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pinned, setPinned] = useState(false);
  const [chartPinId, setChartPinId] = useState<string | null>(null);
  const [productLine, setProductLine] = useState(PRODUCT_LINES[0]);
  const [region, setRegion] = useState(REGIONS[0]);
  const [focus, setFocus] = useState(FOCUS_AREAS[0]);

  async function handleAsk(overrideQuestion?: string) {
    const q = overrideQuestion ?? question;
    if (!q.trim() || loading || sessionExpired) return;
    setLoading(true);
    setError(null);
    setBlockedEvents(null);
    setPinned(false);
    setChartPinId(null);
    try {
      const r = await askGenie(token, q);
      setResult(r);
      onResult(r);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        onSessionExpired();
        setError("Your session has expired — sign in again to ask new questions.");
      } else if (e instanceof ApiError && e.events) {
        setBlockedEvents(e.events);
      } else if (e instanceof Error) {
        setError(e.message);
      }
    } finally {
      setLoading(false);
    }
  }

  function applyParams() {
    setQuestion(`Show total claims and loss ratio for ${productLine} ${focus.toLowerCase()} in the ${region} region`);
  }

  async function handlePin() {
    if (!result) return;
    try {
      await pinItem(token, "genie", "table", truncateTitle(question) || "Genie result", {
        columns: result.columns, rows: result.rows,
      });
      setPinned(true);
    } catch {
      /* non-critical */
    }
  }

  async function handlePinChart() {
    if (!result) return;
    try {
      if (chartPinId) {
        await deletePinnedItem(token, chartPinId);
        setChartPinId(null);
      } else {
        const { id } = await pinItem(token, "genie", "chart", truncateTitle(question) || "Genie chart", {
          columns: result.columns, rows: result.rows,
        });
        setChartPinId(id);
      }
    } catch {
      /* non-critical */
    }
  }

  return (
    <div className="rz-two-col" style={styles.pageWithSidebar}>
      <aside className="rz-col-left rz-card-col" style={styles.sidebar}>
        <div style={styles.sideLabel}>Query Parameters</div>
        <label style={styles.fieldLabel}>Product line</label>
        <select style={styles.select} value={productLine} onChange={(e) => setProductLine(e.target.value)}>
          {PRODUCT_LINES.map((p) => <option key={p}>{p}</option>)}
        </select>
        <label style={styles.fieldLabel}>Region</label>
        <select style={styles.select} value={region} onChange={(e) => setRegion(e.target.value)}>
          {REGIONS.map((r) => <option key={r}>{r}</option>)}
        </select>
        <label style={styles.fieldLabel}>Analysis focus</label>
        <select style={styles.select} value={focus} onChange={(e) => setFocus(e.target.value)}>
          {FOCUS_AREAS.map((f) => <option key={f}>{f}</option>)}
        </select>
        <button style={styles.applyBtn} onClick={applyParams}>Apply to question</button>
      </aside>

      <div className="rz-col-main" style={styles.page}>
      <div style={styles.promptCard}>
        <label style={styles.label} htmlFor="question">
          Ask your data
        </label>
        <div style={styles.inputRow}>
          <input
            id="question"
            style={styles.input}
            placeholder="e.g. Show me the top 5 claims by amount"
            value={question}
            disabled={sessionExpired}
            onChange={(e) => setQuestion(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleAsk()}
          />
          <button style={styles.askButton} onClick={() => handleAsk()} disabled={loading || sessionExpired}>
            {loading ? "Asking…" : "Ask"}
          </button>
        </div>
        {sessionExpired && (
          <div style={styles.sessionNote}>
            Your session has expired — sign in again (top right) to ask new questions.
          </div>
        )}
      </div>

      {blockedEvents && (
        <div style={styles.blockedCard}>
          <div style={styles.blockedTitle}>This question was blocked by a safety guardrail</div>
          {blockedEvents.map((e, i) => (
            <div key={i} style={styles.blockedEvent}>
              <span style={styles.blockedPolicy}>{e.policy}</span>
              <span>{e.detail}</span>
            </div>
          ))}
        </div>
      )}

      {error && <div style={styles.errorCard}>{error}</div>}

      {result && !blockedEvents && (
        <div style={styles.resultCard}>
          <div style={styles.resultHeader}>
            {result.summary && (
              <div style={styles.summary}>
                <MarkdownLite text={result.summary} />
              </div>
            )}
            <button style={styles.pinButton} onClick={handlePin} disabled={pinned}>
              {pinned ? "📌 Pinned" : "📌 Pin text"}
            </button>
          </div>
          {result.guardrails.grounding?.flagged && (
            <div style={styles.groundingWarning}>
              ⚠ Some figures in this summary couldn't be verified against the returned data.
              Check the Governance panel for details.
            </div>
          )}

          {result.columns.length > 0 ? (
            <>
              <ChatDataChart data={{ columns: result.columns, rows: result.rows }} />
              <div style={styles.chartPinRow}>
                <button style={styles.pinButton} onClick={handlePinChart}>
                  {chartPinId ? "📊 Unpin chart" : "📊 Pin chart"}
                </button>
              </div>
            </>
          ) : (
            <div style={styles.noRows}>No rows returned for this question.</div>
          )}
        </div>
      )}
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  pageWithSidebar: {},
  sidebar: { padding: 20 },
  sideLabel: {
    fontSize: 11.5, fontFamily: "var(--mono)", letterSpacing: 0.5, textTransform: "uppercase",
    color: "var(--ink-soft)", marginBottom: 14,
  },
  fieldLabel: { display: "block", fontSize: 12.5, color: "var(--ink-soft)", marginBottom: 6, marginTop: 14 },
  select: {
    width: "100%", padding: "9px 10px", fontSize: 13.5, border: "1px solid var(--line)",
    borderRadius: 6, color: "var(--primary)", fontWeight: 600, background: "var(--surface)",
  },
  applyBtn: {
    width: "100%", marginTop: 20, padding: "10px 0", background: "var(--primary)", color: "white",
    border: "none", borderRadius: 8, fontWeight: 700, fontSize: 13, cursor: "pointer",
  },
  // overflowY: "auto" is the piece that was missing — min-height:0 (from
  // the .rz-col-main CSS class) lets this pane shrink to fit, but without
  // an explicit overflow here, content taller than that shrunk box just
  // gets clipped by the outer .rz-two-col (overflow:hidden) with no way
  // to reach the hidden part — exactly the "content goes off-screen with
  // no scrollbar" symptom.
  // No maxWidth/margin:auto — previously centered the card in a fixed
  // 860px column, leaving large empty gaps on both sides on wider
  // screens. Now it fills the available width instead.
  page: { flex: 1, padding: "32px 32px 60px", overflowY: "auto" },
  promptCard: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 20,
    marginBottom: 20,
  },
  label: {
    display: "block",
    fontSize: 11.5,
    fontFamily: "var(--mono)",
    letterSpacing: 0.5,
    textTransform: "uppercase",
    color: "var(--ink-soft)",
    marginBottom: 10,
  },
  inputRow: { display: "flex", gap: 10 },
  input: {
    flex: 1,
    padding: "11px 14px",
    fontSize: 14,
    border: "1px solid var(--line)",
    borderRadius: 8,
    outline: "none",
    fontFamily: "var(--sans)",
    background: "var(--surface)",
    color: "var(--ink)",
  },
  askButton: {
    padding: "0 20px",
    background: "var(--primary)",
    color: "white",
    border: "none",
    borderRadius: 8,
    fontWeight: 600,
    fontSize: 13.5,
    cursor: "pointer",
  },
  sessionNote: {
    marginTop: 10,
    fontSize: 12.5,
    color: "#8A5A00",
  },
  blockedCard: {
    background: "var(--danger-soft)",
    border: "1px solid rgba(179,38,30,0.25)",
    borderRadius: 10,
    padding: 16,
    marginBottom: 20,
  },
  blockedTitle: { fontWeight: 700, color: "var(--danger)", marginBottom: 8, fontSize: 13.5 },
  blockedEvent: { display: "flex", gap: 10, fontSize: 12.5, color: "var(--ink)", padding: "4px 0" },
  blockedPolicy: { fontFamily: "var(--mono)", fontWeight: 700 },
  errorCard: {
    background: "var(--paper)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 16,
    fontSize: 13,
    color: "var(--ink-soft)",
    marginBottom: 20,
  },
  resultCard: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 20,
  },
  resultHeader: { display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 },
  pinButton: {
    flexShrink: 0, fontSize: 12, background: "none", border: "1px solid var(--line)", borderRadius: 6,
    padding: "6px 10px", cursor: "pointer", color: "var(--ink-soft)",
  },
  chartPinRow: { display: "flex", justifyContent: "flex-end", marginBottom: 8 },
  summary: { fontSize: 14.5, lineHeight: 1.6, marginTop: 0, marginBottom: 16 },
  groundingWarning: {
    background: "#FFF7E6",
    border: "1px solid #F0C36D",
    borderRadius: 6,
    padding: "8px 10px",
    fontSize: 12.5,
    color: "#8A5A00",
    marginBottom: 14,
  },
  tableWrap: { overflowX: "auto", border: "1px solid var(--line)", borderRadius: 8 },
  table: { width: "100%", borderCollapse: "collapse", fontSize: 12.5 },
  th: {
    textAlign: "left",
    padding: "8px 10px",
    background: "var(--paper)",
    borderBottom: "1px solid var(--line)",
    fontFamily: "var(--mono)",
    fontWeight: 600,
    whiteSpace: "nowrap",
  },
  td: {
    padding: "8px 10px",
    borderBottom: "1px solid var(--line)",
    whiteSpace: "nowrap",
  },
  noRows: { fontSize: 13, color: "var(--ink-soft)" },
};
