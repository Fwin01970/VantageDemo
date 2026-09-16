import { useEffect, useState } from "react";
import {
  askGenie, GenieResult, ApiError, GuardrailEvent, pinItem, deletePinnedItem,
  fetchGenieConfig, GenieConfig,
} from "../lib/api";
import ChatDataChart from "../components/ChatDataChart";
import MarkdownLite from "../components/MarkdownLite";
import { truncateTitle } from "../lib/text";

interface Props {
  token: string;
  onResult: (result: GenieResult) => void;
  sessionExpired: boolean;
  onSessionExpired: () => void;
}

// No hardcoded product lines, regions, or "claims and loss ratio" wording
// here anymore — every bit of that is domain-specific vocabulary that a
// Platform Super Admin configures per tenant (Master Admin → Genie
// Config), since a retail or banking tenant has no concept of "claims"
// at all. This component just renders whatever fields/template/
// suggestions the backend hands it for the logged-in user's tenant.

// Fills a template like "Show {Product line} in {Region}" with the
// currently selected value for each field — {Field Name} placeholders
// come directly from the admin-configured field_name values, so this
// works for ANY domain's vocabulary without this component knowing what
// any of the fields mean.
function fillTemplate(template: string, values: Record<string, string>): string {
  return template.replace(/\{([^}]+)\}/g, (match, fieldName) => {
    const trimmed = fieldName.trim();
    return values[trimmed] ?? match;
  });
}

export default function GeniePage({ token, onResult, sessionExpired, onSessionExpired }: Props) {
  const [question, setQuestion] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<GenieResult | null>(null);
  const [blockedEvents, setBlockedEvents] = useState<GuardrailEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pinned, setPinned] = useState(false);
  const [chartPinId, setChartPinId] = useState<string | null>(null);

  const [config, setConfig] = useState<GenieConfig | null>(null);
  const [configLoading, setConfigLoading] = useState(true);
  const [paramValues, setParamValues] = useState<Record<string, string>>({});

  useEffect(() => {
    let cancelled = false;
    setConfigLoading(true);
    fetchGenieConfig(token)
      .then((cfg) => {
        if (cancelled) return;
        setConfig(cfg);
        // Default every dropdown to its first option, same as the old
        // hardcoded version defaulted to PRODUCT_LINES[0] etc. — just
        // driven by whatever fields this tenant actually has now.
        const defaults: Record<string, string> = {};
        for (const f of cfg.fields) {
          if (f.options.length > 0) defaults[f.field_name] = f.options[0];
        }
        setParamValues(defaults);
      })
      .catch(() => {
        // Non-critical: Genie itself still works with a manually typed
        // question even if the config fetch fails — just no dropdowns
        // or suggestions to help fill it in.
        if (!cancelled) setConfig({ fields: [], template: null, suggested_questions: [] });
      })
      .finally(() => {
        if (!cancelled) setConfigLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

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
    if (!config?.template) return;
    setQuestion(fillTemplate(config.template, paramValues));
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

  const hasFields = !configLoading && (config?.fields.length ?? 0) > 0;
  const hasSuggestions = !configLoading && (config?.suggested_questions.length ?? 0) > 0;

  return (
    <div className="rz-two-col" style={styles.pageWithSidebar}>
      <aside className="rz-col-left rz-card-col" style={styles.sidebar}>
        <div style={styles.sideLabel}>Query Parameters</div>
        {configLoading && <div style={styles.configNote}>Loading…</div>}
        {!configLoading && !hasFields && (
          <div style={styles.configNote}>
            No query parameters have been configured for your organization yet.
            An administrator can set these up from Master Admin.
          </div>
        )}
        {config?.fields.map((f) => (
          <div key={f.field_name}>
            <label style={styles.fieldLabel}>{f.field_name}</label>
            <select
              style={styles.select}
              value={paramValues[f.field_name] ?? ""}
              onChange={(e) => setParamValues((prev) => ({ ...prev, [f.field_name]: e.target.value }))}
            >
              {f.options.map((o) => <option key={o}>{o}</option>)}
            </select>
          </div>
        ))}
        {hasFields && config?.template && (
          <button style={styles.applyBtn} onClick={applyParams}>Apply to question</button>
        )}

        {hasSuggestions && (
          <>
            <div style={{ ...styles.sideLabel, marginTop: 28 }}>Suggested Questions</div>
            <div style={styles.suggestionList}>
              {config!.suggested_questions.map((s, i) => (
                <button
                  key={i}
                  style={styles.suggestionBtn}
                  onClick={() => handleAsk(s)}
                  disabled={loading || sessionExpired}
                >
                  {s}
                </button>
              ))}
            </div>
          </>
        )}
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
            placeholder={config?.suggested_questions[0] ? `e.g. ${config.suggested_questions[0]}` : "Type your question…"}
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
            <div style={styles.cornerBadges}>
              {result.guardrails.grounding && (
                <span
                  style={{
                    ...styles.groundingBadge,
                    ...(result.guardrails.grounding.flagged ? styles.groundingBadgeFlagged : styles.groundingBadgeOk),
                  }}
                  title={result.guardrails.grounding.flagged
                    ? "Some figures in this summary couldn't be traced back to the returned rows."
                    : "Every figure in this summary traces back to the returned rows."}
                >
                  {result.guardrails.grounding.flagged ? "⚠" : "✓"} Grounding {result.guardrails.grounding.score}/100
                </span>
              )}
              <button style={styles.pinButton} onClick={handlePin} disabled={pinned}>
                {pinned ? "📌 Pinned" : "📌 Pin text"}
              </button>
            </div>
          </div>

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
  configNote: { fontSize: 12.5, color: "var(--ink-soft)", lineHeight: 1.5 },
  fieldLabel: { display: "block", fontSize: 12.5, color: "var(--ink-soft)", marginBottom: 6, marginTop: 14 },
  select: {
    width: "100%", padding: "9px 10px", fontSize: 13.5, border: "1px solid var(--line)",
    borderRadius: 6, color: "var(--primary)", fontWeight: 600, background: "var(--surface)",
  },
  applyBtn: {
    width: "100%", marginTop: 20, padding: "10px 0", background: "var(--primary)", color: "white",
    border: "none", borderRadius: 8, fontWeight: 700, fontSize: 13, cursor: "pointer",
  },
  suggestionList: { display: "flex", flexDirection: "column", gap: 6 },
  suggestionBtn: {
    textAlign: "left", fontSize: 12.5, padding: "8px 10px", border: "1px solid var(--line)",
    borderRadius: 6, background: "var(--surface)", color: "var(--ink)", cursor: "pointer",
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
  cornerBadges: { display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 6, flexShrink: 0 },
  groundingBadge: { fontSize: 11, fontFamily: "var(--mono)", borderRadius: 4, padding: "3px 7px", border: "1px solid", whiteSpace: "nowrap" },
  groundingBadgeOk: { background: "rgba(22,138,82,0.08)", color: "#168A52", borderColor: "rgba(22,138,82,0.3)" },
  groundingBadgeFlagged: { background: "#FFF7E6", color: "#8A5A00", borderColor: "#F0C36D" },
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
