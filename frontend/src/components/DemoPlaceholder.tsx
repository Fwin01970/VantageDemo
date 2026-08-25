interface Props {
  title: string;
  description: string;
  onLoginClick: () => void;
}

export default function DemoPlaceholder({ title, description, onLoginClick }: Props) {
  return (
    <div style={styles.wrap}>
      <div style={styles.card}>
        <div style={styles.icon}>🔒</div>
        <div style={styles.title}>{title}</div>
        <p style={styles.desc}>{description}</p>
        <button style={styles.loginBtn} onClick={onLoginClick}>
          Login to try this with your data →
        </button>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  wrap: { display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100%", padding: 40 },
  card: {
    maxWidth: 420, textAlign: "center", background: "var(--surface)", border: "1px solid var(--line)",
    borderRadius: 12, padding: 32,
  },
  icon: { fontSize: 28, marginBottom: 12 },
  title: { fontSize: 16, fontWeight: 700, marginBottom: 8 },
  desc: { fontSize: 13.5, color: "var(--ink-soft)", lineHeight: 1.6, marginBottom: 20 },
  loginBtn: {
    background: "var(--primary)", color: "white", border: "none", borderRadius: 8,
    padding: "10px 20px", fontSize: 13, fontWeight: 600, cursor: "pointer",
  },
};
