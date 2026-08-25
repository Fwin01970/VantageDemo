interface Props {
  title: string;
  message: string;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmDialog({ title, message, confirmLabel = "Confirm", danger, onConfirm, onCancel }: Props) {
  return (
    <div style={styles.overlay} onClick={onCancel}>
      <div style={styles.dialog} onClick={(e) => e.stopPropagation()}>
        <div style={styles.title}>{title}</div>
        <div style={styles.message}>{message}</div>
        <div style={styles.actions}>
          <button style={styles.cancelBtn} onClick={onCancel}>Cancel</button>
          <button style={{ ...styles.confirmBtn, ...(danger ? styles.confirmBtnDanger : {}) }} onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: {
    position: "fixed", inset: 0, background: "rgba(18,22,28,0.45)",
    display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100,
  },
  dialog: {
    width: "min(380px, 90vw)", background: "var(--surface)", border: "1px solid var(--line)",
    borderRadius: 12, padding: 22, boxShadow: "var(--shadow)",
  },
  title: { fontWeight: 700, fontSize: 15, marginBottom: 8, color: "var(--ink)" },
  message: { fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.6, marginBottom: 20 },
  actions: { display: "flex", justifyContent: "flex-end", gap: 10 },
  cancelBtn: {
    background: "none", border: "1px solid var(--line)", borderRadius: 8, padding: "8px 16px",
    fontSize: 13, fontWeight: 600, cursor: "pointer", color: "var(--ink)",
  },
  confirmBtn: {
    background: "var(--primary)", color: "white", border: "none", borderRadius: 8, padding: "8px 16px",
    fontSize: 13, fontWeight: 600, cursor: "pointer",
  },
  confirmBtnDanger: { background: "var(--danger)" },
};
