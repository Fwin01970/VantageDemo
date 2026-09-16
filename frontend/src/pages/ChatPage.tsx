import { useState, useRef, useEffect } from "react";
import {
  sendChatMessage, fetchConversations, fetchConversationMessages, fetchUseCases, pinItem, deletePinnedItem, deleteConversation,
  ApiError, GuardrailEvent, ConversationSummary, UseCase, ChatChartData, GenieResult,
} from "../lib/api";
import ConfirmDialog from "../components/ConfirmDialog";
import ConversationHistoryPanel from "../components/ConversationHistoryPanel";
import ChatDataChart from "../components/ChatDataChart";
import MarkdownLite from "../components/MarkdownLite";
import { truncateTitle } from "../lib/text";

const SIDEBAR_VISIBLE_LIMIT = 6;

interface Props {
  token: string;
  sessionExpired: boolean;
  onSessionExpired: () => void;
  pendingQuestion?: string | null;
  onPendingQuestionConsumed?: () => void;
  // Optional so ChatPage doesn't hard-require a caller that doesn't
  // care (e.g. tests) — but AppShell wires this to the same lastResult
  // state Genie feeds, so the Governance panel's SQL/Guardrails/
  // Grounding tabs reflect Ask AI activity too, not just Genie's.
  onResult?: (result: GenieResult) => void;
}

interface DisplayMessage {
  role: "user" | "assistant";
  content: string;
  toolUsed?: boolean;
  toolAvailable?: boolean;
  blockedEvents?: GuardrailEvent[] | null;
  chartData?: ChatChartData | null;
  grounding?: { score: number; flagged: boolean } | null;
  // Presence of an id means "currently pinned" — tracked separately for
  // text vs. chart, since either, both, or neither may be pinned
  // independently for the same message.
  textPinId?: string | null;
  chartPinId?: string | null;
}

const PRODUCT_LINES = ["Motor", "Property", "General Liability", "Business Interruption"];
const REGIONS = ["Midwest", "Northeast", "South", "West"];
const FOCUS_AREAS = ["Risk", "Trend", "Forecast", "Anomalies"];

function formatRelativeTime(iso: string): string {
  const date = new Date(iso);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.round(diffMs / 60000);
  if (diffMin < 1) return "just now";
  if (diffMin < 60) return `${diffMin} minute${diffMin === 1 ? "" : "s"} ago`;
  const diffHr = Math.round(diffMin / 60);
  if (diffHr < 24) return `${diffHr} hour${diffHr === 1 ? "" : "s"} ago`;
  const isSameYear = date.getFullYear() === now.getFullYear();
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric", year: isSameYear ? undefined : "numeric" });
}

function isToday(iso: string): boolean {
  const d = new Date(iso);
  const now = new Date();
  return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
}

function groupConversationsByDate(conversations: ConversationSummary[]): { label: string; items: ConversationSummary[] }[] {
  const today = conversations.filter((c) => isToday(c.updated_at));
  const previous = conversations.filter((c) => !isToday(c.updated_at));
  const groups: { label: string; items: ConversationSummary[] }[] = [];
  if (today.length > 0) groups.push({ label: "Today", items: today });
  if (previous.length > 0) groups.push({ label: "Previous", items: previous });
  return groups;
}

export default function ChatPage({ token, sessionExpired, onSessionExpired, pendingQuestion, onPendingQuestionConsumed, onResult }: Props) {
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [useCases, setUseCases] = useState<UseCase[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [productLine, setProductLine] = useState(PRODUCT_LINES[0]);
  const [region, setRegion] = useState(REGIONS[0]);
  const [focus, setFocus] = useState(FOCUS_AREAS[0]);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  const bottomRef = useRef<HTMLDivElement>(null);

  function refreshConversations() {
    fetchConversations(token).then(setConversations).catch(() => {});
  }

  useEffect(() => {
    refreshConversations();
    fetchUseCases(token).then(setUseCases).catch(() => {});
  }, [token]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  useEffect(() => {
    if (pendingQuestion) {
      send(pendingQuestion);
      onPendingQuestionConsumed?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingQuestion]);

  async function openConversation(id: string) {
    setConversationId(id);
    try {
      const msgs = await fetchConversationMessages(token, id);
      setMessages(msgs.map((m) => ({ role: m.role, content: m.content, chartData: m.chart_data ?? null })));
    } catch {
      setMessages([]);
    }
  }

  function startNewConversation() {
    setConversationId(null);
    setMessages([]);
    setError(null);
  }

  async function handleDeleteConversation(e: React.MouseEvent, id: string) {
    e.stopPropagation();
    setPendingDeleteId(id);
  }

  async function confirmDelete() {
    if (!pendingDeleteId) return;
    await deleteConversation(token, pendingDeleteId);
    if (pendingDeleteId === conversationId) {
      startNewConversation();
    }
    setPendingDeleteId(null);
    refreshConversations();
  }

  async function send(userText: string) {
    if (!userText.trim() || loading || sessionExpired) return;
    setError(null);
    const nextMessages: DisplayMessage[] = [...messages, { role: "user", content: userText }];
    setMessages(nextMessages);
    setInput("");
    setLoading(true);

    try {
      const res = await sendChatMessage(token, conversationId, userText);
      // A blocked FIRST message returns an empty conversation_id (nothing
      // was actually created/persisted server-side) — don't track it,
      // or the next message would incorrectly look like a reply within
      // a "real" conversation that doesn't exist.
      if (res.conversation_id) {
        setConversationId(res.conversation_id);
      }
      if (res.blocked) {
        setMessages([...nextMessages, {
          role: "assistant", content: "This message was blocked by a safety guardrail.", blockedEvents: res.blocked_events,
        }]);
      } else {
        setMessages([...nextMessages, {
          role: "assistant", content: res.reply, toolUsed: res.tool_used, toolAvailable: res.tool_available,
          chartData: res.chart_data, grounding: res.grounding,
        }]);
      }
      // Feeds the SAME lastResult state Genie populates, so the
      // Governance panel's SQL/Guardrails/Grounding tabs reflect Ask AI
      // activity too — previously those tabs only ever updated from the
      // Genie tab, so they stayed empty no matter how many questions
      // were asked here.
      onResult?.({
        sql: res.sql,
        summary: res.blocked ? null : res.reply,
        columns: res.chart_data?.columns ?? [],
        rows: res.chart_data?.rows ?? [],
        row_count: res.chart_data?.rows?.length ?? 0,
        conversation_id: res.conversation_id || conversationId || "",
        message_id: "",
        guardrails: {
          input_events: res.blocked ? (res.blocked_events ?? []) : res.guardrail_input_events,
          llm_check: { ran: !res.blocked, provider_used: res.provider_used },
          grounding: res.grounding,
        },
      });
      if (res.conversation_id) {
        refreshConversations();
      }
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) {
        onSessionExpired();
        setError("Your session has expired — sign in again to keep chatting.");
      } else if (e instanceof Error) {
        setError(e.message);
      }
      // Even on failure, the user's message may have been persisted
      // server-side before the LLM call failed — refresh so the sidebar
      // reflects that rather than looking empty/stale.
      refreshConversations();
    } finally {
      setLoading(false);
    }
  }

  // The user's question, not the assistant's answer, makes a far better
  // pin title — answers routinely open with boilerplate like "Based on
  // company data for the current year in our records...", which reads
  // as meaningless filler once shortened, whereas the question itself
  // ("What's our loss ratio by product line?") is exactly what the
  // pinned card is about. Falls back to the answer only if, for some
  // reason, there's no preceding user message to pull from.
  function titleFor(index: number): string {
    for (let i = index - 1; i >= 0; i--) {
      if (messages[i].role === "user") return truncateTitle(messages[i].content);
    }
    return truncateTitle(messages[index].content);
  }

  async function handlePinText(index: number) {
    const m = messages[index];
    try {
      if (m.textPinId) {
        await deletePinnedItem(token, m.textPinId);
        setMessages((prev) => prev.map((msg, i) => (i === index ? { ...msg, textPinId: null } : msg)));
      } else {
        const { id } = await pinItem(token, "ask_ai", "insight", titleFor(index), { text: m.content });
        setMessages((prev) => prev.map((msg, i) => (i === index ? { ...msg, textPinId: id } : msg)));
      }
    } catch {
      /* pin/unpin failure is non-critical; silently ignore for now */
    }
  }

  async function handlePinChart(index: number) {
    const m = messages[index];
    if (!m.chartData) return;
    try {
      if (m.chartPinId) {
        await deletePinnedItem(token, m.chartPinId);
        setMessages((prev) => prev.map((msg, i) => (i === index ? { ...msg, chartPinId: null } : msg)));
      } else {
        const { id } = await pinItem(token, "ask_ai", "chart", titleFor(index), {
          columns: m.chartData.columns, rows: m.chartData.rows,
        });
        setMessages((prev) => prev.map((msg, i) => (i === index ? { ...msg, chartPinId: id } : msg)));
      }
    } catch {
      /* pin/unpin failure is non-critical; silently ignore for now */
    }
  }

  function runAnalysis() {
    send(`Analyze ${productLine} insurance ${focus.toLowerCase()} in the ${region} region.`);
  }

  const suggestions = useCases.slice(0, 4).map((u) => u.sample_question);

  return (
    <div className="rz-three-col" style={styles.page}>
      <aside className="rz-col-left rz-card-col" style={styles.historySidebar}>
        <button style={styles.newConvoBtn} onClick={startNewConversation}>
          <span style={styles.plusIcon}>+</span> New conversation
        </button>

        {conversations.length === 0 && <div style={styles.emptyHistory}>No conversations yet.</div>}

        {groupConversationsByDate(conversations.slice(0, SIDEBAR_VISIBLE_LIMIT)).map((group) => (
          <div key={group.label}>
            <div style={styles.groupLabel}>{group.label}</div>
            {group.items.map((c) => (
              <div
                key={c.id}
                style={{ ...styles.convoRow, ...(c.id === conversationId ? styles.convoItemActive : {}) }}
              >
                <button style={styles.convoItem} onClick={() => openConversation(c.id)}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" style={styles.convoIcon}>
                    <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
                  </svg>
                  <div style={styles.convoText}>
                    <div style={styles.convoTitle}>{c.title}</div>
                    <div style={styles.convoTime}>{formatRelativeTime(c.updated_at)}</div>
                  </div>
                </button>
                <button
                  style={styles.deleteConvoBtn}
                  title="Delete conversation (kept in the audit log)"
                  onClick={(e) => handleDeleteConversation(e, c.id)}
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        ))}

        {conversations.length > SIDEBAR_VISIBLE_LIMIT && (
          <button style={styles.moreBtn} onClick={() => setHistoryOpen(true)}>
            More… ({conversations.length - SIDEBAR_VISIBLE_LIMIT} older)
          </button>
        )}
      </aside>

      {pendingDeleteId && (
        <ConfirmDialog
          title="Do you want to delete this conversation?"
          message="It will still be visible in the Governance audit log."
          confirmLabel="Delete"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setPendingDeleteId(null)}
        />
      )}

      {historyOpen && (
        <ConversationHistoryPanel
          token={token}
          onOpenConversation={(id) => openConversation(id)}
          onClose={() => { setHistoryOpen(false); refreshConversations(); }}
        />
      )}

      <div className="rz-col-main rz-card-col" style={styles.chatColumn}>
        <div style={styles.messages}>
          {messages.length === 0 && (
            <div style={styles.emptyState}>
              Ask a question, or pick a suggestion on the right. This assistant
              can hold a conversation — feel free to ask follow-ups.
            </div>
          )}

          {messages.map((m, i) => (
            <div key={i} style={{ ...styles.bubbleRow, justifyContent: m.role === "user" ? "flex-end" : "flex-start" }}>
              <div style={m.role === "user" ? styles.userBubble : styles.assistantBubble}>
                {m.blockedEvents ? (
                  <div>
                    <div style={styles.blockedTitle}>Blocked by a safety guardrail</div>
                    {m.blockedEvents.map((ev, j) => (
                      <div key={j} style={styles.blockedEvent}><span style={{ fontWeight: 700 }}>{ev.policy}</span> — {ev.detail}</div>
                    ))}
                  </div>
                ) : (
                  <>
                    <div style={styles.bubbleText}>
                      {m.role === "assistant" ? <MarkdownLite text={m.content} /> : m.content}
                    </div>
                    {m.role === "assistant" && m.chartData && (
                      <>
                        <ChatDataChart data={m.chartData} />
                        <div style={styles.chartPinRow}>
                          <button style={styles.pinBtn} onClick={() => handlePinChart(i)} title="Pin chart to dashboard">
                            {m.chartPinId ? "📊 Unpin chart" : "📊 Pin chart"}
                          </button>
                        </div>
                      </>
                    )}
                    {m.role === "assistant" && (
                      <div style={styles.badgeRow}>
                        {m.toolUsed ? (
                          <span style={styles.badgeData}>✓ Used real company data</span>
                        ) : (
                          <span style={styles.badgeGeneral}>
                            {m.toolAvailable === false ? "General knowledge (no data access this turn)" : "General knowledge"}
                          </span>
                        )}
                        {m.grounding && (
                          <span
                            style={{ ...styles.groundingBadge, ...(m.grounding.flagged ? styles.groundingBadgeFlagged : styles.groundingBadgeOk) }}
                            title={m.grounding.flagged
                              ? "Some figures in this answer couldn't be traced back to the real data returned."
                              : "Every figure in this answer traces back to the real data returned."}
                          >
                            {m.grounding.flagged ? "⚠" : "✓"} Grounding {m.grounding.score}/100
                          </span>
                        )}
                        <button style={styles.pinBtn} onClick={() => handlePinText(i)} title="Pin text to dashboard">
                          {m.textPinId ? "📌 Unpin text" : "📌 Pin text"}
                        </button>
                      </div>
                    )}
                  </>
                )}
              </div>
            </div>
          ))}

          {loading && (
            <div style={{ ...styles.bubbleRow, justifyContent: "flex-start" }}>
              <div style={styles.assistantBubble}><span style={styles.typingDots}>Thinking…</span></div>
            </div>
          )}
          {error && <div style={styles.errorNote}>{error}</div>}
          <div ref={bottomRef} />
        </div>

        <div style={styles.inputRow}>
          <input
            style={styles.input}
            placeholder={sessionExpired ? "Sign in again to keep chatting" : "Type a message…"}
            value={input}
            disabled={sessionExpired}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && send(input)}
          />
          <button style={styles.sendBtn} onClick={() => send(input)} disabled={loading || sessionExpired}>Send</button>
        </div>
      </div>

      <aside className="rz-col-right rz-card-col" style={styles.rightPanel}>
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
        <button style={styles.runBtn} onClick={runAnalysis} disabled={loading || sessionExpired}>▶ Run analysis</button>

        {suggestions.length > 0 && (
          <>
            <div style={{ ...styles.sideLabel, marginTop: 24 }}>Suggested questions</div>
            {suggestions.map((s, i) => (
              <button key={i} style={styles.suggestionBtn} onClick={() => send(s)} disabled={loading || sessionExpired}>
                {s}
              </button>
            ))}
          </>
        )}
      </aside>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {},
  historySidebar: { padding: 16 },
  newConvoBtn: {
    width: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
    padding: "12px 0", background: "var(--primary)", color: "white", border: "none",
    borderRadius: 10, fontWeight: 700, fontSize: 13.5, cursor: "pointer", marginBottom: 20,
  },
  plusIcon: { fontSize: 15, fontWeight: 700, lineHeight: 1 },
  groupLabel: {
    fontSize: 10.5, fontFamily: "var(--mono)", letterSpacing: 0.6, textTransform: "uppercase",
    color: "var(--ink-soft)", fontWeight: 700, margin: "18px 4px 8px",
  },
  sideLabel: {
    fontSize: 10.5, fontFamily: "var(--mono)", letterSpacing: 0.5, textTransform: "uppercase",
    color: "var(--ink-soft)", marginBottom: 10,
  },
  emptyHistory: { fontSize: 12, color: "var(--ink-soft)" },
  convoRow: {
    display: "flex", alignItems: "center", borderRadius: 9, marginBottom: 3, color: "var(--ink-soft)",
  },
  convoItem: {
    flex: 1, minWidth: 0, display: "flex", alignItems: "flex-start", gap: 10, textAlign: "left",
    background: "none", border: "none", borderRadius: 9, padding: 11, cursor: "pointer",
    color: "inherit",
  },
  convoItemActive: { background: "var(--primary-soft)", color: "var(--primary)" },
  deleteConvoBtn: {
    flexShrink: 0, background: "none", border: "none", color: "var(--ink-soft)", cursor: "pointer",
    fontSize: 12, padding: "6px 10px", opacity: 0.6,
  },
  convoIcon: { flexShrink: 0, marginTop: 1 },
  convoText: { minWidth: 0, flex: 1 },
  convoTitle: {
    fontSize: 12, fontWeight: 600, color: "inherit", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
  },
  convoTime: { fontSize: 10, color: "var(--ink-soft)", marginTop: 3 },
  moreBtn: {
    width: "100%", marginTop: 10, padding: "9px 0", background: "none", color: "var(--primary)",
    border: "1px solid var(--line)", borderRadius: 8, fontSize: 12.5, fontWeight: 600, cursor: "pointer",
  },
  chatColumn: { display: "flex", flexDirection: "column", minHeight: 0 },
  // minHeight: 0 is required here (not just flex: 1) — without it, a flex
  // item won't shrink below its content's natural size, so once enough
  // messages accumulate this pane refuses to be the thing that scrolls
  // and instead pushes the whole app shell taller than the viewport,
  // which drags the footer up into the middle of the page.
  messages: { flex: 1, minHeight: 0, overflowY: "auto", padding: "24px 28px", display: "flex", flexDirection: "column", gap: 14 },
  emptyState: { color: "var(--ink-soft)", fontSize: 13.5, lineHeight: 1.6, maxWidth: 480 },
  bubbleRow: { display: "flex" },
  userBubble: { maxWidth: "70%", background: "var(--primary)", color: "white", padding: "10px 14px", borderRadius: "12px 12px 2px 12px", fontSize: 13.5, lineHeight: 1.5 },
  assistantBubble: { maxWidth: "70%", background: "var(--surface)", border: "1px solid var(--line)", padding: "10px 14px", borderRadius: "12px 12px 12px 2px", fontSize: 13.5, lineHeight: 1.5 },
  bubbleText: { whiteSpace: "pre-wrap" },
  badgeRow: { marginTop: 8, display: "flex", alignItems: "center", gap: 8 },
  chartPinRow: { marginTop: 6, display: "flex", justifyContent: "flex-end" },
  badgeData: { fontSize: 11, fontFamily: "var(--mono)", background: "var(--accent-soft)", color: "var(--accent)", borderRadius: 4, padding: "2px 6px" },
  badgeGeneral: { fontSize: 11, fontFamily: "var(--mono)", background: "var(--paper)", color: "var(--ink-soft)", border: "1px solid var(--line)", borderRadius: 4, padding: "2px 6px" },
  groundingBadge: { fontSize: 11, fontFamily: "var(--mono)", borderRadius: 4, padding: "2px 6px", border: "1px solid" },
  groundingBadgeOk: { background: "rgba(22,138,82,0.08)", color: "#168A52", borderColor: "rgba(22,138,82,0.3)" },
  groundingBadgeFlagged: { background: "#FFF7E6", color: "#8A5A00", borderColor: "#F0C36D" },
  pinBtn: { fontSize: 11, background: "none", border: "1px solid var(--line)", borderRadius: 4, padding: "2px 6px", cursor: "pointer", color: "var(--ink-soft)" },
  blockedTitle: { fontWeight: 700, color: "var(--danger)", marginBottom: 4, fontSize: 12.5 },
  blockedEvent: { fontSize: 12, color: "var(--ink)" },
  typingDots: { color: "var(--ink-soft)", fontSize: 13 },
  errorNote: { fontSize: 12.5, color: "var(--danger)", background: "var(--danger-soft)", border: "1px solid rgba(179,38,30,0.25)", borderRadius: 8, padding: "8px 12px" },
  inputRow: { display: "flex", gap: 10, padding: "16px 28px", borderTop: "1px solid var(--line)" },
  input: { flex: 1, padding: "11px 14px", fontSize: 14, border: "1px solid var(--line)", borderRadius: 8, outline: "none", background: "var(--surface)", color: "var(--ink)" },
  sendBtn: { padding: "0 22px", background: "var(--primary)", color: "white", border: "none", borderRadius: 8, fontWeight: 600, fontSize: 13.5, cursor: "pointer" },
  rightPanel: { padding: 20, overflowY: "auto" },
  fieldLabel: { display: "block", fontSize: 12.5, color: "var(--ink-soft)", marginBottom: 6, marginTop: 14 },
  select: { width: "100%", padding: "9px 10px", fontSize: 13.5, border: "1px solid var(--line)", borderRadius: 6, color: "var(--primary)", fontWeight: 600, background: "var(--surface)" },
  runBtn: { width: "100%", marginTop: 20, padding: "11px 0", background: "var(--primary)", color: "white", border: "none", borderRadius: 8, fontWeight: 700, fontSize: 13.5, cursor: "pointer" },
  suggestionBtn: {
    display: "block", width: "100%", textAlign: "left", padding: "9px 11px", marginBottom: 7, fontSize: 12,
    background: "var(--paper)", border: "1px solid var(--line)", borderRadius: 8, cursor: "pointer", color: "var(--ink)",
  },
};
