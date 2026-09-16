import { useEffect, useState } from "react";
import {
  fetchPinnedItems, deletePinnedItem, fetchMyDashboardShares, shareDashboard, unshareDashboard,
  PinnedItem, DashboardShare, ApiError,
} from "../lib/api";
import ChatDataChart from "../components/ChatDataChart";
import MarkdownLite from "../components/MarkdownLite";
import ResizableCard from "../components/ResizableCard";

interface Props {
  token: string;
  onSessionExpired: () => void;
}

export default function DashboardPage({ token, onSessionExpired }: Props) {
  const [items, setItems] = useState<PinnedItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [shareModalOpen, setShareModalOpen] = useState(false);

  function load() {
    fetchPinnedItems(token)
      .then(setItems)
      .catch((e: ApiError) => {
        if (e.status === 401) onSessionExpired();
        setError(e.message);
      });
  }

  useEffect(load, [token]);

  async function handleRefresh() {
    setRefreshing(true);
    setError(null);
    try {
      const fresh = await fetchPinnedItems(token);
      setItems(fresh);
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.status === 401) onSessionExpired();
        setError(e.message);
      }
    } finally {
      setRefreshing(false);
    }
  }

  async function handleRemove(id: string) {
    await deletePinnedItem(token, id);
    setItems((prev) => (prev ? prev.filter((i) => i.id !== id) : prev));
  }

  if (error) return <div style={styles.page}><div style={styles.errorCard}>{error}</div></div>;
  if (!items) return <div style={styles.page}><div style={styles.loading}>Loading dashboard…</div></div>;

  return (
    <div style={styles.page}>
      <div style={styles.heading}>
        <div>
          <h1 style={styles.h1}>Dashboards</h1>
          <p style={styles.sub}>
            Pinned from Ask AI, Genie, and Use Cases. Your whole dashboard is private to you —
            use "Share dashboard" to let one specific person on your team see it too.
          </p>
        </div>
        <div style={styles.headingActions}>
          <button style={styles.shareDashboardBtn} onClick={() => setShareModalOpen(true)}>
            👥 Share dashboard
          </button>
          <button style={styles.refreshBtn} onClick={handleRefresh} disabled={refreshing} title="Refresh pinned items">
            <span style={{ display: "inline-block", ...(refreshing ? styles.spin : {}) }}>⟳</span>
            {refreshing ? "Refreshing…" : "Refresh"}
          </button>
        </div>
      </div>

      {items.length === 0 ? (
        <div style={styles.emptyCard}>
          No pinned items yet. Go to Ask AI, Genie, or Use Cases, get an answer, and click "Pin" to add it here.
        </div>
      ) : (
        <div style={styles.grid}>
          {items.map((item) => (
            <ResizableCard key={item.id} style={styles.card}>
              <div style={styles.cardInner}>
                <div style={styles.cardHeader}>
                  <div>
                    <div style={styles.cardTitle}>{item.title}</div>
                    <div style={styles.cardSub}>
                      Pinned from {item.source === "genie" ? "Genie" : item.source === "use_case" ? "a Use Case" : "Ask AI"}
                      {!item.is_mine && item.owner_name && ` · shared by ${item.owner_name}`}
                    </div>
                  </div>
                  {item.is_mine && (
                    <button style={styles.removeBtn} onClick={() => handleRemove(item.id)} title="Remove">✕</button>
                  )}
                </div>
                <div style={styles.cardBody}>
                  {item.item_type === "insight" && (
                    <div style={styles.insightBox}>
                      <MarkdownLite text={item.payload.text} />
                    </div>
                  )}
                  {item.item_type === "table" && item.payload.columns && (
                    <div style={styles.tableWrap}>
                      <table style={styles.table}>
                        <thead>
                          <tr>{item.payload.columns.map((c: string) => <th key={c} style={styles.th}>{c}</th>)}</tr>
                        </thead>
                        <tbody>
                          {item.payload.rows.slice(0, 8).map((row: any[], i: number) => (
                            <tr key={i}>{row.map((cell, j) => <td key={j} style={styles.td}>{cell ?? "—"}</td>)}</tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                  {item.item_type === "chart" && item.payload.columns && item.payload.rows && (
                    <ChatDataChart data={{ columns: item.payload.columns, rows: item.payload.rows }} />
                  )}
                </div>
              </div>
            </ResizableCard>
          ))}
        </div>
      )}

      {shareModalOpen && (
        <ShareDashboardModal token={token} onClose={() => setShareModalOpen(false)} onSessionExpired={onSessionExpired} />
      )}
    </div>
  );
}

// Whole-dashboard sharing lives here, not on individual pin cards — one
// popup, enter an email, that person (if they already have a login in
// your company) can now see everything you've pinned, present and
// future, until you revoke it.
function ShareDashboardModal({ token, onClose, onSessionExpired }: { token: string; onClose: () => void; onSessionExpired: () => void }) {
  const [shares, setShares] = useState<DashboardShare[] | null>(null);
  const [email, setEmail] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function load() {
    fetchMyDashboardShares(token).then(setShares).catch((e: ApiError) => {
      if (e.status === 401) onSessionExpired();
    });
  }
  useEffect(load, [token]);

  async function handleShare() {
    if (!email.trim() || busy) return;
    setBusy(true);
    setMsg(null);
    try {
      const res = await shareDashboard(token, email.trim());
      setMsg(`Shared with ${res.shared_with}.`);
      setEmail("");
      load();
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.status === 401) onSessionExpired();
        setMsg(e.message);
      }
    } finally {
      setBusy(false);
    }
  }

  async function handleRevoke(shareId: string) {
    await unshareDashboard(token, shareId);
    setShares((prev) => (prev ? prev.filter((s) => s.id !== shareId) : prev));
  }

  return (
    <div style={styles.modalOverlay} onClick={onClose}>
      <div style={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div style={styles.modalTitle}>Share your dashboard</div>
        <p style={styles.modalSub}>
          The person you share with must already have a login in your company. They'll be able to see
          every pin on your dashboard, now and in the future, until you remove them below.
        </p>

        <label style={styles.modalLabel}>Email address</label>
        <div style={styles.modalInputRow}>
          <input
            style={styles.modalInput}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="e.g. raj.mehta@company.com"
            onKeyDown={(e) => e.key === "Enter" && handleShare()}
          />
          <button style={styles.modalShareBtn} onClick={handleShare} disabled={busy}>
            {busy ? "Sharing…" : "Share"}
          </button>
        </div>
        {msg && <div style={styles.modalMsg}>{msg}</div>}

        {shares && shares.length > 0 && (
          <>
            <div style={styles.modalListTitle}>Currently shared with</div>
            {shares.map((s) => (
              <div key={s.id} style={styles.modalShareRow}>
                <div>
                  <div style={{ fontWeight: 600, fontSize: 13 }}>{s.display_name}</div>
                  <div style={{ fontSize: 11.5, color: "var(--ink-soft)" }}>{s.email}</div>
                </div>
                <button style={styles.modalRevokeBtn} onClick={() => handleRevoke(s.id)}>Remove</button>
              </div>
            ))}
          </>
        )}

        <button style={styles.modalCloseBtn} onClick={onClose}>Done</button>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  // flex:1 + minHeight:0 lets this fill the remaining space inside
  // AppShell's flex column; overflowY:auto is what actually makes THIS
  // element scroll instead of silently clipping content past the
  // viewport. No maxWidth/margin:auto — the page uses the full
  // available width instead of being centered in a fixed column.
  page: { flex: 1, minHeight: 0, overflowY: "auto", padding: "32px 32px 60px", width: "100%" },
  heading: { marginBottom: 20, display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 },
  headingActions: { display: "flex", gap: 8, flexShrink: 0 },
  h1: { fontSize: 22, margin: "0 0 6px" },
  sub: { fontSize: 13, color: "var(--ink-soft)", margin: 0 },
  shareDashboardBtn: {
    display: "flex", alignItems: "center", gap: 6, padding: "8px 14px", fontSize: 12.5, fontWeight: 600,
    background: "var(--primary)", border: "1px solid var(--primary)", borderRadius: 8, color: "white",
    cursor: "pointer", flexShrink: 0, whiteSpace: "nowrap",
  },
  refreshBtn: {
    display: "flex", alignItems: "center", gap: 6, padding: "8px 14px", fontSize: 12.5, fontWeight: 600,
    background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 8, color: "var(--primary)",
    cursor: "pointer", flexShrink: 0, whiteSpace: "nowrap",
  },
  spin: { animation: "rz-spin 0.8s linear infinite" },
  loading: { color: "var(--ink-soft)", fontSize: 13.5 },
  errorCard: { background: "var(--danger-soft)", color: "var(--danger)", padding: 16, borderRadius: 10, fontSize: 13 },
  emptyCard: {
    background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 24,
    textAlign: "center", color: "var(--ink-soft)", fontSize: 13.5,
  },
  grid: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" },
  card: {
    background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, overflow: "hidden",
  },
  cardInner: { display: "flex", flexDirection: "column", width: "100%", height: "100%" },
  cardHeader: { display: "flex", justifyContent: "space-between", alignItems: "flex-start", padding: "14px 16px", borderBottom: "1px solid var(--line)", flexShrink: 0 },
  cardTitle: { fontSize: 13.5, fontWeight: 700, lineHeight: 1.4, wordBreak: "break-word" },
  cardSub: { fontSize: 11, color: "var(--ink-soft)", marginTop: 2 },
  removeBtn: { background: "none", border: "1px solid var(--line)", borderRadius: 6, width: 26, height: 26, cursor: "pointer", color: "var(--ink-soft)", flexShrink: 0 },
  cardBody: { padding: 16, overflow: "auto", flex: 1, minHeight: 0 },
  insightBox: { background: "var(--primary-soft)", border: "1px solid var(--line)", borderRadius: 8, padding: 12, fontSize: 12.5, lineHeight: 1.6, color: "var(--ink)" },
  tableWrap: { overflowX: "auto" },
  table: { width: "100%", borderCollapse: "collapse", fontSize: 11.5 },
  th: { textAlign: "left", padding: "6px 8px", background: "var(--paper)", borderBottom: "1px solid var(--line)", fontFamily: "var(--mono)", whiteSpace: "nowrap" },
  td: { padding: "6px 8px", borderBottom: "1px solid var(--line)", whiteSpace: "nowrap" },

  modalOverlay: {
    position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)", display: "flex",
    alignItems: "center", justifyContent: "center", zIndex: 1000,
  },
  modal: {
    background: "var(--surface)", borderRadius: 12, padding: 24, width: 420, maxWidth: "90vw",
    boxShadow: "0 10px 40px rgba(0,0,0,0.2)",
  },
  modalTitle: { fontSize: 17, fontWeight: 700, marginBottom: 8 },
  modalSub: { fontSize: 12.5, color: "var(--ink-soft)", lineHeight: 1.5, marginBottom: 16 },
  modalLabel: { fontSize: 12, fontWeight: 600, display: "block", marginBottom: 6 },
  modalInputRow: { display: "flex", gap: 8 },
  modalInput: {
    flex: 1, padding: "9px 11px", fontSize: 13.5, border: "1px solid var(--line)", borderRadius: 6,
    background: "var(--paper)", color: "var(--ink)",
  },
  modalShareBtn: {
    padding: "0 16px", background: "var(--primary)", color: "white", border: "none",
    borderRadius: 6, fontWeight: 600, fontSize: 13, cursor: "pointer",
  },
  modalMsg: { marginTop: 10, fontSize: 12.5, color: "var(--ink)" },
  modalListTitle: { fontSize: 11, fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.4, color: "var(--ink-soft)", marginTop: 20, marginBottom: 8 },
  modalShareRow: { display: "flex", justifyContent: "space-between", alignItems: "center", padding: "8px 0", borderBottom: "1px solid var(--line)" },
  modalRevokeBtn: { fontSize: 11.5, background: "none", border: "1px solid var(--danger)", color: "var(--danger)", borderRadius: 6, padding: "4px 10px", cursor: "pointer" },
  modalCloseBtn: {
    marginTop: 20, width: "100%", padding: "9px 0", background: "none", border: "1px solid var(--line)",
    borderRadius: 6, fontWeight: 600, fontSize: 13, cursor: "pointer", color: "var(--ink)",
  },
};
