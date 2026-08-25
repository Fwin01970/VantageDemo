import { useEffect, useState } from "react";
import { fetchPinnedItems, deletePinnedItem, PinnedItem, ApiError } from "../lib/api";
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
          <p style={styles.sub}>Pinned from Ask AI and Genie. Click 📌 Pin on any result to add it here.</p>
        </div>
        <button style={styles.refreshBtn} onClick={handleRefresh} disabled={refreshing} title="Refresh pinned items">
          <span style={{ display: "inline-block", ...(refreshing ? styles.spin : {}) }}>⟳</span>
          {refreshing ? "Refreshing…" : "Refresh"}
        </button>
      </div>

      {items.length === 0 ? (
        <div style={styles.emptyCard}>
          No pinned items yet. Go to Ask AI or Genie, get an answer, and click "Pin" to add it here.
        </div>
      ) : (
        <div style={styles.grid}>
          {items.map((item) => (
            <ResizableCard key={item.id} style={styles.card}>
              <div style={styles.cardInner}>
                <div style={styles.cardHeader}>
                  <div>
                    <div style={styles.cardTitle}>{item.title}</div>
                    <div style={styles.cardSub}>Pinned from {item.source === "genie" ? "Genie" : "Ask AI"}</div>
                  </div>
                  <button style={styles.removeBtn} onClick={() => handleRemove(item.id)} title="Remove">✕</button>
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
  h1: { fontSize: 22, margin: "0 0 6px" },
  sub: { fontSize: 13, color: "var(--ink-soft)", margin: 0 },
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
  // Flex-wrap instead of a fixed grid, so each card's own size (set via
  // the resize handles) determines layout instead of every card being
  // forced into equal grid cells.
  grid: { display: "flex", flexWrap: "wrap", gap: 16, alignItems: "flex-start" },
  card: {
    background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, overflow: "hidden",
  },
  cardInner: { display: "flex", flexDirection: "column", width: "100%", height: "100%" },
  cardHeader: { display: "flex", justifyContent: "space-between", alignItems: "flex-start", padding: "14px 16px", borderBottom: "1px solid var(--line)", flexShrink: 0 },
  cardTitle: { fontSize: 13.5, fontWeight: 700 },
  cardSub: { fontSize: 11, color: "var(--ink-soft)", marginTop: 2 },
  removeBtn: { background: "none", border: "1px solid var(--line)", borderRadius: 6, width: 26, height: 26, cursor: "pointer", color: "var(--ink-soft)", flexShrink: 0 },
  cardBody: { padding: 16, overflow: "auto", flex: 1, minHeight: 0 },
  insightBox: { background: "var(--primary-soft)", border: "1px solid var(--line)", borderRadius: 8, padding: 12, fontSize: 12.5, lineHeight: 1.6, color: "var(--ink)" },
  tableWrap: { overflowX: "auto" },
  table: { width: "100%", borderCollapse: "collapse", fontSize: 11.5 },
  th: { textAlign: "left", padding: "6px 8px", background: "var(--paper)", borderBottom: "1px solid var(--line)", fontFamily: "var(--mono)", whiteSpace: "nowrap" },
  td: { padding: "6px 8px", borderBottom: "1px solid var(--line)", whiteSpace: "nowrap" },
};
