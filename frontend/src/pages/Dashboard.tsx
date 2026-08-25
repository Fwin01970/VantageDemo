import { useEffect, useState } from "react";
import { fetchMe, MeResponse } from "../lib/api";
import { tenantColor, initials } from "../lib/tenantColor";

interface Props {
  token: string;
  onLogout: () => void;
}

const PERMISSION_LABELS: Record<string, string> = {
  "data:query": "Ask questions about tenant data",
  "dashboard:manage": "Create and edit dashboards",
  "tenant:manage": "Manage tenant settings, users, and roles",
  "audit:view": "View the audit log",
};

export default function Dashboard({ token, onLogout }: Props) {
  const [me, setMe] = useState<MeResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchMe(token)
      .then(setMe)
      .catch((e) => setError(e.message));
  }, [token]);

  if (error) {
    return (
      <div style={styles.page}>
        <div style={styles.errorCard}>
          <div style={styles.errorTitle}>Couldn't verify your session</div>
          <p style={styles.errorBody}>{error}</p>
          <button style={styles.linkButton} onClick={onLogout}>
            Back to sign in
          </button>
        </div>
      </div>
    );
  }

  if (!me) {
    return <div style={styles.loadingPage}>Loading your account…</div>;
  }

  const color = tenantColor(me.tenant_name);

  return (
    <div style={styles.page}>
      <main style={styles.main}>
        <div style={styles.identityCard}>
          <span style={{ ...styles.avatar, background: color }}>
            {initials(me.display_name)}
          </span>
          <div>
            <div style={styles.welcome}>Welcome, {me.display_name}</div>
            <div style={styles.tenantLine}>
              <span style={{ ...styles.dot, background: color }} aria-hidden />
              {me.tenant_name}
              <span style={styles.industryTag}>{me.industry}</span>
            </div>
          </div>
        </div>

        <div style={styles.grid}>
          <section style={styles.panel}>
            <div style={styles.panelTitle}>Your role</div>
            {me.roles.length === 0 ? (
              <div style={styles.empty}>No role assigned yet.</div>
            ) : (
              me.roles.map((r) => <div key={r} style={styles.roleBadge}>{r}</div>)
            )}
          </section>

          <section style={styles.panel}>
            <div style={styles.panelTitle}>What you can do</div>
            {me.permissions.length === 0 ? (
              <div style={styles.empty}>No permissions granted yet.</div>
            ) : (
              <ul style={styles.permList}>
                {me.permissions.map((p) => (
                  <li key={p} style={styles.permItem}>
                    <span style={styles.permCode}>{p}</span>
                    <span style={styles.permLabel}>
                      {PERMISSION_LABELS[p] ?? "—"}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        
      </main>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { minHeight: "100vh" },
  loadingPage: {
    minHeight: "100vh",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "var(--ink-soft)",
    fontSize: 14,
  },
  errorCard: {
    maxWidth: 420,
    margin: "120px auto",
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 24,
  },
  errorTitle: { fontWeight: 700, marginBottom: 6 },
  errorBody: { fontSize: 13.5, color: "var(--ink-soft)", marginBottom: 14 },
  linkButton: {
    background: "none",
    border: "none",
    color: "var(--accent)",
    fontWeight: 600,
    fontSize: 13.5,
    cursor: "pointer",
    padding: 0,
  },
  topbar: {
    display: "none",
  },
  topbarBrand: { display: "none" },
  brandMark: { display: "none" },
  brandName: { display: "none" },
  logoutButton: { display: "none" },
  main: { maxWidth: 780, margin: "0 auto", padding: "36px 24px 60px" },
  identityCard: {
    display: "flex",
    alignItems: "center",
    gap: 16,
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 20,
    marginBottom: 24,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 999,
    color: "white",
    fontFamily: "var(--mono)",
    fontSize: 16,
    fontWeight: 600,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    flexShrink: 0,
  },
  welcome: { fontSize: 18, fontWeight: 700, marginBottom: 4 },
  tenantLine: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    fontSize: 13.5,
    color: "var(--ink-soft)",
  },
  dot: { width: 8, height: 8, borderRadius: 999, display: "inline-block" },
  industryTag: {
    marginLeft: 6,
    fontFamily: "var(--mono)",
    fontSize: 11,
    textTransform: "uppercase",
    letterSpacing: 0.4,
    background: "var(--paper)",
    border: "1px solid var(--line)",
    borderRadius: 4,
    padding: "2px 6px",
  },
  grid: { display: "grid", gridTemplateColumns: "1fr 1.6fr", gap: 16 },
  panel: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 18,
  },
  panelTitle: {
    fontSize: 11.5,
    fontFamily: "var(--mono)",
    letterSpacing: 0.6,
    textTransform: "uppercase",
    color: "var(--ink-soft)",
    marginBottom: 12,
  },
  empty: { fontSize: 13.5, color: "var(--ink-soft)" },
  roleBadge: {
    display: "inline-block",
    background: "var(--accent-soft)",
    color: "var(--accent)",
    fontWeight: 600,
    fontSize: 13,
    borderRadius: 6,
    padding: "6px 10px",
  },
  permList: { listStyle: "none", margin: 0, padding: 0 },
  permItem: {
    display: "flex",
    flexDirection: "column",
    padding: "8px 0",
    borderBottom: "1px solid var(--line)",
  },
  permCode: { fontFamily: "var(--mono)", fontSize: 12.5, color: "var(--primary)" },
  permLabel: { fontSize: 13, color: "var(--ink-soft)", marginTop: 2 },
  footnote: {
    marginTop: 28,
    fontSize: 12.5,
    lineHeight: 1.6,
    color: "var(--ink-soft)",
    borderTop: "1px solid var(--line)",
    paddingTop: 16,
  },
};
