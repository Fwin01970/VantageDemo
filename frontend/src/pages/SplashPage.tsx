interface Props {
  onStartGuided: () => void;
  onExploreFree: () => void;
}

const BADGES = ["Guardrails", "HITL review", "MLflow governance", "Audit trail", "Genie governed"];

export default function SplashPage({ onStartGuided, onExploreFree }: Props) {
  return (
    <div style={styles.page}>
      <div style={styles.inner}>
        <div style={styles.logoRow}>
          <div style={styles.fdLockup}>
            <span>FULCRUM</span>
            <span>DIGITAL</span>
            <span style={styles.fdBadge}>FD</span>
          </div>
          <div style={styles.divider} />
          <div style={styles.databricksLockup}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
              <path fill="#FF3621" d="M12 2L2 7.5V12l10 5.5L22 12V7.5L12 2zm0 2.18l7.5 4.12-7.5 4.12L4.5 8.3 12 4.18zM2 13.5l10 5.5 10-5.5V16l-10 5.5L2 16v-2.5z" />
            </svg>
            <span>Databricks</span>
          </div>
        </div>

        <div style={styles.wordmarkRow}>
          <span style={styles.wordmarkInfinity}>∞</span>
          <span style={styles.wordmarkText}>
            RYZE<span style={styles.wordmarkLight}>INFINITY</span>
          </span>
        </div>
        <div style={styles.eyebrow}>Fulcrum Digital · Databricks Edition</div>

        <h1 style={styles.headline}>
          Every AI decision your underwriters make — governed, auditable, and safe.
        </h1>
        <p style={styles.subhead}>
          Ryze Infinity wraps Databricks Genie, Delta Lake Gold, and the Mosaic AI Gateway with
          guardrails, human-in-the-loop review, and a compliance-ready audit trail, on your
          existing investment.
        </p>

        <div style={styles.badgeRow}>
          {BADGES.map((b) => (
            <span key={b} style={styles.badge}>{b}</span>
          ))}
        </div>

        <div style={styles.buttonRow}>
          <button style={styles.primaryBtn} onClick={onStartGuided}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z" /></svg>
            Start guided demo
          </button>
          <button style={styles.secondaryBtn} onClick={onExploreFree}>
            Explore freely →
          </button>
        </div>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: "100vh",
    background: "#0a0816",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 40,
    fontFamily: "'Roboto', var(--sans, sans-serif)",
  },
  inner: {
    maxWidth: 760,
    textAlign: "center",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 22,
  },
  logoRow: { display: "flex", alignItems: "center", justifyContent: "center", gap: 20, flexWrap: "wrap" },
  fdLockup: {
    display: "flex", flexDirection: "column", alignItems: "flex-start", lineHeight: 1.05,
    fontSize: 12, fontWeight: 700, color: "#fff", letterSpacing: 0.3, position: "relative",
  },
  fdBadge: {
    position: "absolute", right: -26, bottom: 0, background: "#fff", color: "#0a0816",
    fontSize: 9, fontWeight: 900, padding: "1px 4px", borderRadius: 2,
  },
  divider: { width: 1, height: 28, background: "rgba(255,255,255,0.25)" },
  databricksLockup: { display: "flex", alignItems: "center", gap: 8 },
  wordmarkRow: { display: "flex", alignItems: "center", gap: 10, marginTop: 6 },
  wordmarkInfinity: { fontSize: 30, color: "#fff", fontWeight: 900 },
  wordmarkText: { fontSize: 30, fontWeight: 900, color: "#fff", letterSpacing: -0.5 },
  wordmarkLight: { fontWeight: 300, opacity: 0.85 },
  eyebrow: {
    fontSize: 11, fontWeight: 600, letterSpacing: "0.2em", textTransform: "uppercase",
    color: "rgba(199,141,255,0.6)",
  },
  headline: {
    fontSize: 42, fontWeight: 900, lineHeight: 1.08, letterSpacing: "-0.03em",
    color: "#fff", margin: 0, maxWidth: "18ch",
  },
  subhead: {
    fontSize: 17, lineHeight: 1.6, color: "rgba(255,255,255,0.55)", margin: 0, maxWidth: "54ch",
  },
  badgeRow: { display: "flex", gap: 8, flexWrap: "wrap", justifyContent: "center", marginTop: 4 },
  badge: {
    padding: "6px 14px", borderRadius: 20, background: "rgba(115,0,226,0.18)",
    border: "1px solid rgba(199,141,255,0.25)", color: "#C78DFF", fontSize: 11.5, fontWeight: 600,
  },
  buttonRow: { display: "flex", gap: 14, alignItems: "center", marginTop: 12 },
  primaryBtn: {
    display: "inline-flex", alignItems: "center", gap: 9, padding: "14px 30px",
    border: "none", borderRadius: 4, background: "#7300E2", color: "#fff",
    fontSize: 15, fontWeight: 600, cursor: "pointer",
  },
  secondaryBtn: {
    padding: "14px 20px", border: "1px solid rgba(255,255,255,0.18)", borderRadius: 4,
    background: "transparent", color: "rgba(255,255,255,0.7)", fontSize: 14, fontWeight: 500, cursor: "pointer",
  },
};
