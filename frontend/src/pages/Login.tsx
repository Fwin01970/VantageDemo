import { useEffect, useState } from "react";
import { fetchDemoUsers, login, DemoUser } from "../lib/api";
import { tenantColor, initials } from "../lib/tenantColor";

interface Props {
  onLoggedIn: (token: string) => void;
}

export default function Login({ onLoggedIn }: Props) {
  const [users, setUsers] = useState<DemoUser[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);

  useEffect(() => {
    fetchDemoUsers()
      .then(setUsers)
      .catch((e) => setError(e.message));
  }, []);

  async function handlePick(user: DemoUser) {
    setError(null);
    setPendingId(user.id);
    try {
      const token = await login(user.id);
      onLoggedIn(token);
    } catch (e: any) {
      setError(e.message);
      setPendingId(null);
    }
  }

  const groups = new Map<string, DemoUser[]>();
  (users ?? []).forEach((u) => {
    const list = groups.get(u.tenant_name) ?? [];
    list.push(u);
    groups.set(u.tenant_name, list);
  });

  return (
    <div style={styles.page}>
      <div style={styles.formSide}>
        <div style={styles.brand}>
          <div style={styles.brandLogo}>RI</div>
          <div>
            <div style={styles.brandName}>Ryze Infinity</div>
            <div style={styles.brandSub}>Enterprise Analytics Platform</div>
          </div>
        </div>

        <h1 style={styles.h1}>Welcome back</h1>
        <p style={styles.lead}>Sign in to access Ask AI, Genie, Use Cases, and your dashboards.</p>

        <div style={styles.ssoNote}>
          Real Microsoft sign-in isn't configured yet for this environment — the
          button below shows how it will look once it is. Use a demo account below to sign in for now.
        </div>

        <button style={styles.ssoBtn} disabled>
          <svg width="16" height="16" viewBox="0 0 23 23">
            <rect x="1" y="1" width="10" height="10" fill="#f25022" />
            <rect x="12" y="1" width="10" height="10" fill="#7fba00" />
            <rect x="1" y="12" width="10" height="10" fill="#00a4ef" />
            <rect x="12" y="12" width="10" height="10" fill="#ffb900" />
          </svg>
          Sign in with Microsoft
          <span style={styles.comingSoon}>Coming soon</span>
        </button>

        <div style={styles.divider}><span>DEMO SIGN-IN (TEMPORARY)</span></div>

        {error && <div style={styles.errorBox}>{error}</div>}
        {!users && !error && <div style={styles.loading}>Loading available accounts…</div>}

        {[...groups.entries()].map(([tenantName, members]) => (
          <div key={tenantName}>
            <div style={styles.groupLabel}>
              <span style={{ ...styles.dot, background: tenantColor(tenantName) }} aria-hidden />
              {tenantName}
            </div>
            {members.map((u) => (
              <button
                key={u.id}
                style={styles.demoUser}
                onClick={() => handlePick(u)}
                disabled={pendingId !== null}
              >
                <span style={{ ...styles.avatar, background: tenantColor(u.tenant_name) }}>
                  {initials(u.display_name)}
                </span>
                <span style={styles.userText}>
                  <span style={styles.userName}>{u.display_name}</span>
                  <span style={styles.userEmail}>{u.email}</span>
                </span>
                <span style={styles.action}>
                  {pendingId === u.id ? "Signing in…" : "Sign in →"}
                </span>
              </button>
            ))}
          </div>
        ))}

        <div style={styles.footnote}>
          🔒 Access is restricted to authorised users. This demo sign-in will be
          replaced by real Microsoft Entra ID — nothing else in the app will
          need to change when that happens.
        </div>
      </div>

      <div style={styles.heroSide}>
        <div style={styles.heroTag}><span style={styles.heroDot} />Intelligent Enterprise Analytics</div>
        <h2 style={styles.heroH2}>Turn your data into decisions.</h2>
        <p style={styles.heroLead}>
          Ask questions in natural language, generate governed SQL with Genie,
          and turn insights into live dashboards — scoped to your company automatically.
        </p>
        <div style={styles.previewCard}>
          <div style={styles.previewHeader}>
            <span>Business performance overview</span>
            <span style={styles.exampleBadge}>EXAMPLE</span>
          </div>
          <div style={styles.kpiRow}>
            <div style={styles.kpi}><div style={styles.kpiL}>Open claims</div><div style={styles.kpiV}>248</div></div>
            <div style={styles.kpi}><div style={styles.kpiL}>Loss ratio</div><div style={styles.kpiV}>61.2%</div></div>
            <div style={styles.kpi}><div style={styles.kpiL}>Forecast</div><div style={styles.kpiV}>94.2%</div></div>
          </div>
          <div style={styles.bars}>
            {[46, 68, 57, 82, 63, 94].map((h, i) => (
              <div key={i} style={{ ...styles.bar, height: `${h}%` }} />
            ))}
          </div>
          <div style={styles.illustrative}>Illustrative only — real dashboards come from your own data.</div>
        </div>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { minHeight: "100vh", display: "grid", gridTemplateColumns: "minmax(0,540px) 1fr" },
  formSide: { display: "flex", flexDirection: "column", justifyContent: "center", padding: "60px 72px", background: "var(--paper)" },
  brand: { display: "flex", alignItems: "center", gap: 13, marginBottom: 48 },
  brandLogo: {
    width: 44, height: 44, borderRadius: 12, display: "grid", placeItems: "center",
    background: "linear-gradient(135deg, var(--primary-dark), #786cff)", color: "#fff", fontWeight: 800, fontSize: 15,
  },
  brandName: { fontWeight: 700, fontSize: 17, color: "var(--ink)" },
  brandSub: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 2 },
  h1: { fontSize: 28, margin: "0 0 8px", letterSpacing: -0.6, color: "var(--ink)" },
  lead: { color: "var(--ink-soft)", fontSize: 13.5, lineHeight: 1.6, margin: "0 0 24px", maxWidth: 400 },
  ssoNote: {
    fontSize: 11.5, color: "var(--ink-soft)", background: "var(--primary-soft)", borderRadius: 8,
    padding: "10px 12px", marginBottom: 14, lineHeight: 1.5,
  },
  ssoBtn: {
    width: "100%", height: 46, display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
    border: "1px solid var(--line)", borderRadius: 10, background: "var(--surface)", fontSize: 13.5, fontWeight: 600,
    color: "var(--ink-soft)", marginBottom: 8, cursor: "not-allowed", opacity: 0.6, position: "relative",
  },
  comingSoon: {
    position: "absolute", right: 12, fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4,
    color: "var(--primary)", background: "var(--primary-soft)", padding: "2px 7px", borderRadius: 20, textTransform: "uppercase",
  },
  divider: {
    display: "flex", alignItems: "center", gap: 12, margin: "20px 0 14px", color: "var(--ink-soft)",
    fontSize: 10.5, fontWeight: 700, letterSpacing: 0.5, justifyContent: "center",
  },
  errorBox: {
    fontSize: 12.5, color: "var(--danger)", background: "var(--danger-soft)", borderRadius: 8, padding: "8px 12px", marginBottom: 12,
  },
  loading: { fontSize: 13, color: "var(--ink-soft)", padding: "6px 0" },
  groupLabel: {
    display: "flex", alignItems: "center", gap: 8, fontSize: 11, fontFamily: "var(--mono)", letterSpacing: 0.5,
    textTransform: "uppercase", color: "var(--ink-soft)", margin: "14px 0 7px",
  },
  dot: { width: 7, height: 7, borderRadius: 999, display: "inline-block" },
  demoUser: {
    width: "100%", display: "flex", alignItems: "center", gap: 12, padding: "10px 12px", border: "1px solid var(--line)",
    borderRadius: 10, background: "var(--surface)", marginBottom: 7, textAlign: "left", cursor: "pointer",
  },
  avatar: {
    width: 32, height: 32, borderRadius: "50%", color: "#fff", fontSize: 11.5, fontWeight: 700,
    display: "grid", placeItems: "center", flexShrink: 0,
  },
  userText: { display: "flex", flexDirection: "column" },
  userName: { fontSize: 13, fontWeight: 600, color: "var(--ink)" },
  userEmail: { fontSize: 11, color: "var(--ink-soft)" },
  action: { marginLeft: "auto", fontSize: 11.5, fontWeight: 600, color: "var(--primary)" },
  footnote: { fontSize: 10.5, color: "var(--ink-soft)", marginTop: 22, lineHeight: 1.6, display: "flex", gap: 8 },

  heroSide: {
    position: "relative", overflow: "hidden", padding: "60px 64px", color: "#fff",
    display: "flex", flexDirection: "column", justifyContent: "center",
    background: "radial-gradient(circle at 80% 10%, rgba(255,255,255,0.18), transparent 45%), linear-gradient(150deg, #2c2470, var(--primary) 55%, #786cff)",
  },
  heroTag: {
    display: "inline-flex", alignItems: "center", gap: 7, fontSize: 10.5, fontWeight: 700, letterSpacing: 0.6,
    textTransform: "uppercase", color: "#c9c3ff", marginBottom: 16,
  },
  heroDot: { width: 7, height: 7, borderRadius: "50%", background: "#3ddba0", display: "inline-block" },
  heroH2: { fontSize: 36, lineHeight: 1.15, margin: "0 0 14px", letterSpacing: -1, maxWidth: 480 },
  heroLead: { fontSize: 14, color: "rgba(255,255,255,0.8)", maxWidth: 420, lineHeight: 1.6, marginBottom: 32 },
  previewCard: {
    background: "rgba(255,255,255,0.1)", border: "1px solid rgba(255,255,255,0.2)", borderRadius: 14,
    padding: 18, backdropFilter: "blur(6px)", maxWidth: 480,
  },
  previewHeader: { display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14, fontSize: 12, fontWeight: 700 },
  exampleBadge: { fontSize: 9.5, background: "rgba(61,219,160,0.2)", color: "#6be3b8", padding: "3px 8px", borderRadius: 20, fontWeight: 700 },
  kpiRow: { display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 10, marginBottom: 16 },
  kpi: { background: "rgba(255,255,255,0.08)", borderRadius: 8, padding: 10 },
  kpiL: { fontSize: 9.5, color: "rgba(255,255,255,0.6)" },
  kpiV: { fontSize: 17, fontWeight: 700, marginTop: 4 },
  bars: { display: "flex", alignItems: "flex-end", gap: 8, height: 90 },
  bar: { flex: 1, borderRadius: "4px 4px 0 0", background: "linear-gradient(to top, #786cff, #b7c8ff)" },
  illustrative: { fontSize: 9.5, color: "rgba(255,255,255,0.5)", marginTop: 10, fontStyle: "italic" },
};
