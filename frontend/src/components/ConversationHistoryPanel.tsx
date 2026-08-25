import { useEffect, useState } from "react";
import { ConversationSummary, fetchConversations, deleteConversation } from "../lib/api";
import ConfirmDialog from "./ConfirmDialog";

interface Props {
  token: string;
  onOpenConversation: (id: string) => void;
  onClose: () => void;
}

export default function ConversationHistoryPanel({ token, onOpenConversation, onClose }: Props) {
  const [conversations, setConversations] = useState<ConversationSummary[] | null>(null);
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);

  function load() {
    fetchConversations(token).then(setConversations).catch(() => setConversations([]));
  }

  useEffect(load, [token]);

  async function handleConfirmDelete() {
    if (!pendingDelete) return;
    await deleteConversation(token, pendingDelete);
    setPendingDelete(null);
    load();
  }

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div style={styles.header}>
          <div style={styles.title}>All conversations</div>
          <button style={styles.closeBtn} onClick={onClose} aria-label="Close">✕</button>
        </div>

        <div style={styles.body}>
          {!conversations && <div style={styles.empty}>Loading…</div>}
          {conversations?.length === 0 && <div style={styles.empty}>No conversations yet.</div>}
          {conversations?.map((c) => (
            <div key={c.id} style={styles.row}>
              <button
                style={styles.rowMain}
                onClick={() => {
                  onOpenConversation(c.id);
                  onClose();
                }}
              >
                <div style={styles.rowTitle}>{c.title}</div>
                <div style={styles.rowTime}>{new Date(c.updated_at).toLocaleString()}</div>
              </button>
              <button style={styles.deleteBtn} onClick={() => setPendingDelete(c.id)} title="Delete">✕</button>
            </div>
          ))}
        </div>
      </div>

      {pendingDelete && (
        <ConfirmDialog
          title="Delete conversation?"
          message="It will still be visible in the Governance audit log."
          confirmLabel="Delete"
          danger
          onConfirm={handleConfirmDelete}
          onCancel={() => setPendingDelete(null)}
        />
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: {
    position: "fixed", inset: 0, background: "rgba(18,22,28,0.35)",
    display: "flex", justifyContent: "flex-end", zIndex: 90,
  },
  panel: {
    width: "min(420px, 100%)", height: "100%", background: "var(--surface)",
    borderLeft: "1px solid var(--line)", display: "flex", flexDirection: "column",
    boxShadow: "-8px 0 24px rgba(18,22,28,0.08)",
  },
  header: {
    display: "flex", justifyContent: "space-between", alignItems: "center",
    padding: "18px 20px", borderBottom: "1px solid var(--line)",
  },
  title: { fontWeight: 700, fontSize: 15, color: "var(--ink)" },
  closeBtn: { background: "none", border: "none", fontSize: 16, cursor: "pointer", color: "var(--ink-soft)" },
  // minHeight: 0 — same fix as ChatPage's messages pane; without it this
  // list won't shrink to scroll internally once there are enough rows.
  body: { flex: 1, minHeight: 0, overflowY: "auto", padding: 12 },
  empty: { fontSize: 13, color: "var(--ink-soft)", padding: 16 },
  row: { display: "flex", alignItems: "center", borderRadius: 9, marginBottom: 3 },
  rowMain: {
    flex: 1, minWidth: 0, display: "block", textAlign: "left", background: "none", border: "none",
    borderRadius: 9, padding: 11, cursor: "pointer", color: "var(--ink)",
  },
  rowTitle: { fontSize: 13, fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" },
  rowTime: { fontSize: 11, color: "var(--ink-soft)", marginTop: 2 },
  deleteBtn: {
    flexShrink: 0, background: "none", border: "none", color: "var(--ink-soft)", cursor: "pointer",
    fontSize: 12, padding: "6px 10px",
  },
};
