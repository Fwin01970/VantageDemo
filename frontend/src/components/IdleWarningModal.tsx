interface Props {
  onStayActive: () => void;
}

export default function IdleWarningModal({ onStayActive }: Props) {
  return (
    <div style={styles.overlay}>
      <div style={styles.card}>
        <div style={styles.title}>Still there?</div>
        <p style={styles.body}>
          You've been inactive for a while — you'll be signed out shortly to keep your account secure.
        </p>
        <button style={styles.btn} onClick={onStayActive}>Stay signed in</button>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: {
    position: "fixed", inset: 0, zIndex: 900, background: "rgba(0,0,0,0.4)",
    display: "flex", alignItems: "center", justifyContent: "center", padding: 24,
  },
  card: {
    maxWidth: 360, background: "var(--surface, #fff)", borderRadius: 12, padding: 24,
    boxShadow: "0 24px 60px rgba(0,0,0,0.3)", textAlign: "center",
  },
  title: { fontSize: 16, fontWeight: 700, marginBottom: 8, color: "var(--ink, #111)" },
  body: { fontSize: 13.5, color: "var(--ink-soft, #666)", lineHeight: 1.6, marginBottom: 18 },
  btn: {
    background: "var(--primary, #5b4fd6)", color: "#fff", border: "none", borderRadius: 8,
    padding: "10px 22px", fontSize: 13.5, fontWeight: 700, cursor: "pointer",
  },
};
