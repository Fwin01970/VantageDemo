const FIXTURE_PERMISSIONS: { code: string; label: string }[] = [
  { code: "audit:view", label: "View the audit log" },
  { code: "dashboard:manage", label: "Create and edit dashboards" },
  { code: "data:query", label: "Ask questions about tenant data" },
  { code: "genie:access", label: "—" },
  { code: "tenant:manage", label: "Manage tenant settings, users, and roles" },
];

export default function DemoHomePage() {
  return (
    <div style={styles.page}>
      <main style={styles.main}>
        <div style={styles.identityCard}>
          <span style={styles.avatar}>SC</span>
          <div>
            <div style={styles.welcome}>Welcome, Sarah Chen</div>
            <div style={styles.tenantLine}>
              <span style={styles.dot} aria-hidden />
              ABC Insurance (Demo)
              <span style={styles.industryTag}>INSURANCE</span>
            </div>
          </div>
        </div>

        <div style={styles.grid}>
          <section style={styles.panel}>
            <div style={styles.panelTitle}>Your role</div>
            <div style={styles.roleBadge}>Claims Director</div>
          </section>

          <section style={styles.panel}>
            <div style={styles.panelTitle}>What you can do</div>
            <ul style={styles.permList}>
              {FIXTURE_PERMISSIONS.map((p) => (
                <li key={p.code} style={styles.permItem}>
                  <span style={styles.permCode}>{p.code}</span>
                  <span style={styles.permLabel}>{p.label}</span>
                </li>
              ))}
            </ul>
          </section>
        </div>

        <p style={styles.footnote}>
          You're exploring Ryze Infinity with sample data — nothing here reflects a real
          workspace. Click <strong>Login</strong> in the top right and sign in with your
          real credentials to see your own data.
        </p>
      </main>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { minHeight: "100%" },
  main: { maxWidth: 780, margin: "0 auto", padding: "36px 24px 60px" },
  identityCard: {
    display: "flex", alignItems: "center", gap: 16, background: "var(--surface)",
    border: "1px solid var(--line)", borderRadius: 10, padding: 20, marginBottom: 24,
  },
  avatar: {
    width: 48, height: 48, borderRadius: 999, background: "#0F6E56", color: "white",
    fontFamily: "var(--mono)", fontSize: 16, fontWeight: 600, display: "flex",
    alignItems: "center", justifyContent: "center", flexShrink: 0,
  },
  welcome: { fontSize: 18, fontWeight: 700, marginBottom: 4 },
  tenantLine: { display: "flex", alignItems: "center", gap: 8, fontSize: 13.5, color: "var(--ink-soft)" },
  dot: { width: 8, height: 8, borderRadius: 999, display: "inline-block", background: "#0F6E56" },
  industryTag: {
    marginLeft: 6, fontFamily: "var(--mono)", fontSize: 11, textTransform: "uppercase",
    letterSpacing: 0.4, background: "var(--paper)", border: "1px solid var(--line)",
    borderRadius: 4, padding: "2px 6px",
  },
  grid: { display: "grid", gridTemplateColumns: "1fr 1.6fr", gap: 16 },
  panel: { background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 10, padding: 18 },
  panelTitle: {
    fontSize: 11.5, fontFamily: "var(--mono)", letterSpacing: 0.6, textTransform: "uppercase",
    color: "var(--ink-soft)", marginBottom: 12,
  },
  roleBadge: {
    display: "inline-block", background: "var(--accent-soft)", color: "var(--accent)",
    fontWeight: 600, fontSize: 13, borderRadius: 6, padding: "6px 10px",
  },
  permList: { listStyle: "none", margin: 0, padding: 0 },
  permItem: { display: "flex", flexDirection: "column", padding: "8px 0", borderBottom: "1px solid var(--line)" },
  permCode: { fontFamily: "var(--mono)", fontSize: 12.5, color: "var(--primary)" },
  permLabel: { fontSize: 13, color: "var(--ink-soft)", marginTop: 2 },
  footnote: {
    marginTop: 28, fontSize: 12.5, lineHeight: 1.6, color: "var(--ink-soft)",
    borderTop: "1px solid var(--line)", paddingTop: 16,
  },
};
