import { useEffect, useState } from "react";
import {
  GenieResult, AuditEntry, fetchAuditLog, ApiError,
  GuardrailActivityEntry, HitlReview, fetchGuardrailActivity, fetchHitlQueue, decideHitlCase,
} from "../lib/api";

interface Props {
  token: string;
  lastResult: GenieResult | null;
  onClose: () => void;
  onSessionExpired?: () => void;
}

type Tab = "activity" | "hitl" | "sql" | "guardrails" | "grounding" | "audit";

export default function GovernancePanel({ token, lastResult, onClose, onSessionExpired }: Props) {
  // "activity" first — the guardrail proxy layer's live activity feed and
  // review queue are the thing worth leading with in a client demo, not
  // a per-question SQL/grounding tab that's empty until you've asked
  // something in Genie specifically.
  const [tab, setTab] = useState<Tab>("activity");

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div style={styles.header}>
          <div>
            <div style={styles.title}>Governance</div>
            <div style={styles.subtitle}>
              Every question passes through a guardrail proxy layer — jailbreak/PII/fairness/scope
              checks — before it ever reaches an LLM or the data warehouse.
            </div>
          </div>
          <button style={styles.closeBtn} onClick={onClose} aria-label="Close">
            ✕
          </button>
        </div>

        <div style={styles.tabs}>
          {(["activity", "hitl", "sql", "guardrails", "grounding", "audit"] as Tab[]).map((t) => (
            <button
              key={t}
              style={{ ...styles.tabBtn, ...(tab === t ? styles.tabBtnActive : {}) }}
              onClick={() => setTab(t)}
            >
              {t === "activity" && "Activity"}
              {t === "hitl" && "HITL Review"}
              {t === "sql" && "SQL"}
              {t === "guardrails" && "Guardrails"}
              {t === "grounding" && "Grounding"}
              {t === "audit" && "Audit Log"}
            </button>
          ))}
        </div>

        <div style={styles.body}>
          {tab === "activity" && <ActivityTab token={token} onSessionExpired={onSessionExpired} />}
          {tab === "hitl" && <HitlTab token={token} onSessionExpired={onSessionExpired} />}
          {tab === "sql" && <SqlTab result={lastResult} />}
          {tab === "guardrails" && <GuardrailsTab result={lastResult} />}
          {tab === "grounding" && <GroundingTab result={lastResult} />}
          {tab === "audit" && <AuditTab token={token} />}
        </div>
      </div>
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return <div style={styles.empty}>{text}</div>;
}

// Human-readable label + tone for each guardrail action name, so the
// demo reads as "Jailbreak attempt blocked" instead of the raw
// "chat.message.blocked" action string used internally.
function describeActivity(entry: GuardrailActivityEntry): { label: string; tone: "block" | "flag" | "warn" } {
  const policyFromDetails = (entry.details?.events?.[0]?.policy as string | undefined) || (entry.details?.check as string | undefined);
  if (entry.action === "chat.message.hitl_flagged") return { label: "Flagged for human review", tone: "flag" };
  if (entry.action === "chat.llm_guardrail_unavailable") return { label: "Guardrail LLM check unavailable (failed open, regex-only)", tone: "warn" };
  if (entry.action === "chat.llm_unavailable") return { label: "AI provider unavailable", tone: "warn" };
  if (entry.action === "chat.message.blocked") {
    const reasonText = entry.details?.reason || (entry.details?.check === "off_topic" ? "Off-topic question" : undefined);
    if (policyFromDetails === "JAILBREAK" || entry.details?.layer === "llm" && !entry.details?.check) {
      return { label: "Jailbreak / prompt-injection attempt blocked", tone: "block" };
    }
    if (entry.details?.check === "off_topic") return { label: "Off-topic question blocked", tone: "block" };
    return { label: reasonText ? `Blocked — ${reasonText}` : "Question blocked by guardrail", tone: "block" };
  }
  return { label: entry.action, tone: "warn" };
}

function ActivityTab({ token, onSessionExpired }: { token: string; onSessionExpired?: () => void }) {
  const [entries, setEntries] = useState<GuardrailActivityEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchGuardrailActivity(token)
      .then(setEntries)
      .catch((e: ApiError) => {
        if (e.status === 401) onSessionExpired?.();
        setError(e.message);
      });
  }, [token]);

  if (error) return <Empty text={`Couldn't load guardrail activity: ${error}`} />;
  if (!entries) return <Empty text="Loading…" />;
  if (entries.length === 0) return <Empty text="No guardrail activity yet — ask a question in Ask AI to generate some." />;

  return (
    <div>
      <div style={styles.sectionLabel}>Recent proxy-layer decisions (this tenant)</div>
      {entries.map((e) => {
        const { label, tone } = describeActivity(e);
        return (
          <div key={e.id} style={styles.activityRow}>
            <span style={{ ...styles.activityDot, ...(tone === "block" ? styles.dotBlock : tone === "flag" ? styles.dotFlag : styles.dotWarn) }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={styles.activityLabel}>{label}</div>
              {e.details?.message && <div style={styles.activityMsg}>&ldquo;{String(e.details.message).slice(0, 140)}&rdquo;</div>}
              <div style={styles.activityTime}>{new Date(e.created_at).toLocaleString()}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function HitlTab({ token, onSessionExpired }: { token: string; onSessionExpired?: () => void }) {
  const [reviews, setReviews] = useState<HitlReview[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<"pending" | "all">("pending");
  const [busyId, setBusyId] = useState<string | null>(null);

  function load() {
    fetchHitlQueue(token, filter === "pending" ? "pending" : undefined)
      .then(setReviews)
      .catch((e: ApiError) => {
        if (e.status === 401) onSessionExpired?.();
        setError(e.message);
      });
  }

  useEffect(load, [token, filter]);

  async function handleDecision(id: string, decision: "approved" | "rejected") {
    setBusyId(id);
    try {
      await decideHitlCase(token, id, decision);
      load();
    } catch (e) {
      if (e instanceof ApiError) setError(e.message);
    } finally {
      setBusyId(null);
    }
  }

  if (error) return <Empty text={`Couldn't load the review queue: ${error}`} />;
  if (!reviews) return <Empty text="Loading…" />;

  return (
    <div>
      <div style={styles.hitlFilterRow}>
        <div style={styles.sectionLabel}>Human-in-the-loop queue</div>
        <div style={styles.toggle}>
          <button
            style={{ ...styles.toggleBtn, ...(filter === "pending" ? styles.toggleBtnActive : {}) }}
            onClick={() => setFilter("pending")}
          >
            Pending
          </button>
          <button
            style={{ ...styles.toggleBtn, ...(filter === "all" ? styles.toggleBtnActive : {}) }}
            onClick={() => setFilter("all")}
          >
            All
          </button>
        </div>
      </div>

      {reviews.length === 0 ? (
        <Empty text={filter === "pending" ? "No cases waiting for review." : "No HITL cases recorded yet."} />
      ) : (
        reviews.map((r) => (
          <div key={r.id} style={styles.hitlCard}>
            <div style={styles.hitlQuestion}>&ldquo;{r.question}&rdquo;</div>
            <div style={styles.hitlMeta}>
              {r.check_type} · asked by {r.user_name || "unknown user"} · {new Date(r.created_at).toLocaleString()}
            </div>
            <div style={styles.hitlReason}>{r.reason}</div>
            {r.status === "pending" ? (
              <div style={styles.hitlActions}>
                <button
                  style={styles.approveBtn}
                  disabled={busyId === r.id}
                  onClick={() => handleDecision(r.id, "approved")}
                >
                  ✓ Approve (answer was appropriate)
                </button>
                <button
                  style={styles.rejectBtn}
                  disabled={busyId === r.id}
                  onClick={() => handleDecision(r.id, "rejected")}
                >
                  ✕ Reject (confirm block)
                </button>
              </div>
            ) : (
              <div style={{ ...styles.hitlStatusBadge, ...(r.status === "approved" ? styles.hitlApproved : styles.hitlRejected) }}>
                {r.status === "approved" ? "Approved" : "Rejected"} by {r.reviewed_by_name || "reviewer"}
                {r.reviewed_at && ` · ${new Date(r.reviewed_at).toLocaleString()}`}
              </div>
            )}
          </div>
        ))
      )}
    </div>
  );
}

function SqlTab({ result }: { result: GenieResult | null }) {
  if (!result) return <Empty text="Ask a question first — the generated SQL will appear here." />;
  if (!result.sql) return <Empty text="Genie didn't generate SQL for the last question (e.g. it was out of scope)." />;
  return <pre style={styles.code}>{result.sql}</pre>;
}

function GuardrailsTab({ result }: { result: GenieResult | null }) {
  if (!result) return <Empty text="Ask a question first — guardrail activity will appear here." />;
  const { input_events, llm_check } = result.guardrails;
  return (
    <div>
      <div style={styles.sectionLabel}>Regex pre-checks (jailbreak / PII / fairness)</div>
      {input_events.length === 0 ? (
        <Empty text="No regex guardrail events on the last question." />
      ) : (
        input_events.map((e, i) => (
          <div key={i} style={styles.eventRow}>
            <span style={styles.eventPolicy}>{e.policy}</span>
            <span style={styles.eventDetail}>{e.detail}</span>
          </div>
        ))
      )}
      <div style={{ ...styles.sectionLabel, marginTop: 16 }}>LLM semantic check (second pass)</div>
      {llm_check.ran ? (
        <div style={styles.eventRow}>
          <span style={styles.eventPolicy}>PASSED</span>
          <span style={styles.eventDetail}>via {llm_check.provider_used}</span>
        </div>
      ) : (
        <Empty text="LLM check did not run this time (all providers unreachable, or the question was already blocked by regex). See Audit Log for details." />
      )}
    </div>
  );
}

function GroundingTab({ result }: { result: GenieResult | null }) {
  if (!result) return <Empty text="Ask a question first — the grounding score will appear here." />;
  const g = result.guardrails.grounding;
  if (!g) return <Empty text="No grounding score — the last answer had no summary/rows to check." />;
  return (
    <div>
      <div style={styles.scoreBig}>{g.score}<span style={{ fontSize: 16 }}>/100</span></div>
      <div style={{ ...styles.eventDetail, marginTop: 6 }}>
        {g.flagged
          ? "Flagged — some figures in the summary could not be traced back to the returned rows."
          : "Not flagged — figures in the summary trace back to the returned rows."}
      </div>
    </div>
  );
}

function AuditTab({ token }: { token: string }) {
  const [entries, setEntries] = useState<AuditEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAuditLog(token)
      .then(setEntries)
      .catch((e: ApiError) => setError(e.message));
  }, [token]);

  if (error) return <Empty text={`Couldn't load the audit log: ${error}`} />;
  if (!entries) return <Empty text="Loading…" />;
  if (entries.length === 0) return <Empty text="No audit entries yet." />;

  return (
    <div>
      {entries.map((e) => (
        <div key={e.id} style={styles.auditRow}>
          <div style={styles.auditHeader}>
            <span style={styles.auditAction}>{e.action}</span>
            <span style={styles.auditTime}>{new Date(e.created_at).toLocaleString()}</span>
          </div>
          {Object.keys(e.details).length > 0 && (
            <pre style={styles.auditDetails}>{JSON.stringify(e.details, null, 2)}</pre>
          )}
        </div>
      ))}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: {
    position: "fixed",
    inset: 0,
    background: "rgba(18,22,28,0.35)",
    display: "flex",
    justifyContent: "flex-end",
    zIndex: 50,
  },
  panel: {
    width: "min(520px, 100%)",
    height: "100%",
    background: "var(--surface)",
    borderLeft: "1px solid var(--line)",
    display: "flex",
    flexDirection: "column",
    boxShadow: "-8px 0 24px rgba(18,22,28,0.08)",
  },
  header: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "flex-start",
    padding: "18px 20px",
    borderBottom: "1px solid var(--line)",
  },
  title: { fontWeight: 700, fontSize: 15 },
  subtitle: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 3, maxWidth: 360 },
  closeBtn: {
    background: "none",
    border: "none",
    fontSize: 16,
    cursor: "pointer",
    color: "var(--ink-soft)",
    padding: 4,
  },
  tabs: { display: "flex", borderBottom: "1px solid var(--line)", padding: "0 12px" },
  tabBtn: {
    background: "none",
    border: "none",
    borderBottom: "2px solid transparent",
    padding: "12px 12px",
    fontSize: 12.5,
    fontWeight: 600,
    color: "var(--ink-soft)",
    cursor: "pointer",
  },
  tabBtnActive: {
    color: "var(--accent)",
    borderBottom: "2px solid var(--accent)",
  },
  // minHeight: 0 lets this pane actually shrink and scroll internally
  // instead of forcing the fixed-height panel taller than the viewport
  // once the audit log (or any tab) has enough content — same bug as
  // ChatPage's messages pane.
  body: { padding: 20, overflowY: "auto", flex: 1, minHeight: 0 },
  empty: { fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.6 },
  code: {
    background: "var(--paper)",
    border: "1px solid var(--line)",
    borderRadius: 6,
    padding: 12,
    fontFamily: "var(--mono)",
    fontSize: 12,
    whiteSpace: "pre-wrap",
    wordBreak: "break-word",
  },
  sectionLabel: {
    fontSize: 11,
    fontFamily: "var(--mono)",
    letterSpacing: 0.5,
    textTransform: "uppercase",
    color: "var(--ink-soft)",
    marginBottom: 8,
  },
  eventRow: {
    display: "flex",
    gap: 10,
    padding: "8px 0",
    borderBottom: "1px solid var(--line)",
    fontSize: 12.5,
  },
  eventPolicy: {
    fontFamily: "var(--mono)",
    fontWeight: 700,
    color: "var(--primary)",
    flexShrink: 0,
  },
  eventDetail: { color: "var(--ink-soft)" },
  scoreBig: { fontFamily: "var(--mono)", fontSize: 36, fontWeight: 700, color: "var(--primary)" },
  auditRow: { padding: "10px 0", borderBottom: "1px solid var(--line)" },
  auditHeader: { display: "flex", justifyContent: "space-between", fontSize: 12.5 },
  auditAction: { fontFamily: "var(--mono)", fontWeight: 700, color: "var(--primary)" },
  auditTime: { color: "var(--ink-soft)" },
  auditDetails: {
    marginTop: 6,
    fontSize: 11,
    background: "var(--paper)",
    border: "1px solid var(--line)",
    borderRadius: 6,
    padding: 8,
    whiteSpace: "pre-wrap",
    wordBreak: "break-word",
  },
  // Activity tab
  activityRow: {
    display: "flex", gap: 10, padding: "10px 0", borderBottom: "1px solid var(--line)",
  },
  activityDot: { width: 8, height: 8, borderRadius: "50%", marginTop: 5, flexShrink: 0 },
  dotBlock: { background: "var(--danger)" },
  dotFlag: { background: "#F4B942" },
  dotWarn: { background: "var(--ink-soft)" },
  activityLabel: { fontSize: 12.5, fontWeight: 600, color: "var(--ink)" },
  activityMsg: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 2, fontStyle: "italic" },
  activityTime: { fontSize: 10.5, color: "var(--ink-soft)", marginTop: 3 },
  // HITL tab
  hitlFilterRow: { display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 },
  toggle: { display: "flex", gap: 4 },
  toggleBtn: {
    fontSize: 11, padding: "3px 10px", borderRadius: 6, border: "1px solid var(--line)",
    background: "var(--surface)", color: "var(--ink)", cursor: "pointer",
  },
  toggleBtnActive: { background: "var(--primary)", color: "#fff", borderColor: "var(--primary)" },
  hitlCard: {
    background: "var(--paper)", border: "1px solid var(--line)", borderRadius: 8,
    padding: 12, marginBottom: 10,
  },
  hitlQuestion: { fontSize: 13, fontWeight: 600, color: "var(--ink)" },
  hitlMeta: { fontSize: 10.5, color: "var(--ink-soft)", marginTop: 3, textTransform: "uppercase", fontFamily: "var(--mono)", letterSpacing: 0.3 },
  hitlReason: { fontSize: 12, color: "var(--ink-soft)", marginTop: 8, lineHeight: 1.5 },
  hitlActions: { display: "flex", gap: 8, marginTop: 10 },
  approveBtn: {
    flex: 1, fontSize: 11.5, fontWeight: 600, padding: "7px 10px", borderRadius: 6,
    border: "1px solid var(--success, #168A52)", background: "transparent", color: "#168A52", cursor: "pointer",
  },
  rejectBtn: {
    flex: 1, fontSize: 11.5, fontWeight: 600, padding: "7px 10px", borderRadius: 6,
    border: "1px solid var(--danger)", background: "transparent", color: "var(--danger)", cursor: "pointer",
  },
  hitlStatusBadge: { display: "inline-block", marginTop: 10, fontSize: 11, fontWeight: 600, padding: "4px 10px", borderRadius: 6 },
  hitlApproved: { background: "rgba(22,138,82,0.12)", color: "#168A52" },
  hitlRejected: { background: "var(--danger-soft)", color: "var(--danger)" },
};
