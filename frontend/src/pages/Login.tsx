import { useEffect, useState } from "react";
import {
  fetchDemoUsers, demoLogin, DemoUser, fetchAuthProviders, oauthStartUrl,
  OAuthProviderName, signup, loginWithPassword, ApiError,
} from "../lib/api";
import { tenantColor, initials } from "../lib/tenantColor";

interface Props {
  onLoggedIn: (token: string) => void;
}

const PROVIDER_META: Record<OAuthProviderName, { label: string; icon: JSX.Element }> = {
  microsoft: {
    label: "Microsoft",
    icon: (
      <svg width="16" height="16" viewBox="0 0 23 23">
        <rect x="1" y="1" width="10" height="10" fill="#f25022" />
        <rect x="12" y="1" width="10" height="10" fill="#7fba00" />
        <rect x="1" y="12" width="10" height="10" fill="#00a4ef" />
        <rect x="12" y="12" width="10" height="10" fill="#ffb900" />
      </svg>
    ),
  },
  google: {
    label: "Google",
    icon: (
      <svg width="16" height="16" viewBox="0 0 48 48">
        <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.6 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.1 8 3l5.7-5.7C34.6 6.1 29.6 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.7-.4-3.5z" />
        <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.6 15.9 18.9 13 24 13c3.1 0 5.8 1.1 8 3l5.7-5.7C34.6 6.1 29.6 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
        <path fill="#4CAF50" d="M24 44c5.5 0 10.4-1.9 14.3-5.1l-6.6-5.6C29.6 35.1 26.9 36 24 36c-5.2 0-9.6-3.3-11.2-7.9l-6.5 5C9.6 39.6 16.3 44 24 44z" />
        <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.4-2.4 4.4-4.4 5.9l6.6 5.6C41.4 36 44 30.7 44 24c0-1.3-.1-2.7-.4-3.5z" />
      </svg>
    ),
  },
  github: {
    label: "GitHub",
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="#181717">
        <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
      </svg>
    ),
  },
  facebook: {
    label: "Facebook",
    icon: (
      <svg width="16" height="16" viewBox="0 0 24 24" fill="#1877F2">
        <path d="M24 12.07C24 5.4 18.63 0 12 0S0 5.4 0 12.07C0 18.1 4.39 23.1 10.13 24v-8.44H7.08v-3.49h3.05V9.41c0-3.02 1.79-4.69 4.53-4.69 1.31 0 2.68.24 2.68.24v2.97h-1.51c-1.49 0-1.95.93-1.95 1.89v2.25h3.32l-.53 3.49h-2.79V24C19.61 23.1 24 18.1 24 12.07z" />
      </svg>
    ),
  },
};

type Mode = "signin" | "signup";

export default function Login({ onLoggedIn }: Props) {
  const [mode, setMode] = useState<Mode>("signin");
  const [providers, setProviders] = useState<Record<OAuthProviderName, boolean> | null>(null);
  const [demoUsers, setDemoUsers] = useState<DemoUser[] | null>(null);
  const [showDemo, setShowDemo] = useState(false);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [companyName, setCompanyName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [pendingDemoId, setPendingDemoId] = useState<string | null>(null);

  useEffect(() => {
    fetchAuthProviders().then(setProviders).catch(() => setProviders(null));
    // Fetching, but not surfacing anywhere unless someone explicitly asks
    // to see it — see "Use a sample account instead" below.
    fetchDemoUsers().then(setDemoUsers).catch(() => setDemoUsers(null));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      if (mode === "signin") {
        const token = await loginWithPassword(email, password);
        onLoggedIn(token);
      } else {
        const token = await signup({
          email, password, display_name: displayName, company_name: companyName,
        });
        onLoggedIn(token);
      }
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  async function handlePickDemoUser(user: DemoUser) {
    setError(null);
    setPendingDemoId(user.id);
    try {
      const token = await demoLogin(user.id);
      onLoggedIn(token);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Something went wrong. Please try again.");
      setPendingDemoId(null);
    }
  }

  const availableProviders = (Object.keys(PROVIDER_META) as OAuthProviderName[]).filter(
    (p) => providers?.[p]
  );

  const demoGroups = new Map<string, DemoUser[]>();
  (demoUsers ?? []).forEach((u) => {
    const list = demoGroups.get(u.tenant_name) ?? [];
    list.push(u);
    demoGroups.set(u.tenant_name, list);
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

        <h1 style={styles.h1}>{mode === "signin" ? "Welcome back" : "Create your account"}</h1>
        <p style={styles.lead}>
          {mode === "signin"
            ? "Sign in to access Ask AI, Genie, Use Cases, and your dashboards."
            : "Set up your company's workspace in under a minute."}
        </p>

        {availableProviders.length > 0 && (
          <>
            {availableProviders.map((p) => (
              <a key={p} href={oauthStartUrl(p)} style={styles.ssoBtn}>
                {PROVIDER_META[p].icon}
                Continue with {PROVIDER_META[p].label}
              </a>
            ))}
            <div style={styles.divider}><span>or</span></div>
          </>
        )}

        <form onSubmit={handleSubmit}>
          {mode === "signup" && (
            <>
              <input
                style={styles.input} placeholder="Your name" value={displayName}
                onChange={(e) => setDisplayName(e.target.value)} required
              />
              <input
                style={styles.input} placeholder="Company name" value={companyName}
                onChange={(e) => setCompanyName(e.target.value)} required
              />
            </>
          )}
          <input
            style={styles.input} type="email" placeholder="Email" value={email}
            onChange={(e) => setEmail(e.target.value)} required
          />
          <input
            style={styles.input} type="password" placeholder="Password" value={password}
            onChange={(e) => setPassword(e.target.value)} required minLength={mode === "signup" ? 8 : undefined}
          />
          {error && <div style={styles.errorBox}>{error}</div>}
          <button style={styles.submitBtn} type="submit" disabled={loading}>
            {loading ? "Please wait…" : mode === "signin" ? "Sign in" : "Create account"}
          </button>
        </form>

        <div style={styles.switchModeRow}>
          {mode === "signin" ? (
            <>Don't have an account? <button style={styles.linkBtn} onClick={() => { setMode("signup"); setError(null); }}>Sign up</button></>
          ) : (
            <>Already have an account? <button style={styles.linkBtn} onClick={() => { setMode("signin"); setError(null); }}>Sign in</button></>
          )}
        </div>

        {demoUsers && demoUsers.length > 0 && (
          <div style={styles.demoSection}>
            {!showDemo ? (
              <button style={styles.linkBtn} onClick={() => setShowDemo(true)}>Use a sample account instead</button>
            ) : (
              <>
                <div style={styles.groupTitle}>Sample accounts</div>
                {[...demoGroups.entries()].map(([tenantName, members]) => (
                  <div key={tenantName}>
                    <div style={styles.groupLabel}>
                      <span style={{ ...styles.dot, background: tenantColor(tenantName) }} aria-hidden />
                      {tenantName}
                    </div>
                    {members.map((u) => (
                      <button
                        key={u.id} style={styles.demoUser} onClick={() => handlePickDemoUser(u)}
                        disabled={pendingDemoId !== null}
                      >
                        <span style={{ ...styles.avatar, background: tenantColor(u.tenant_name) }}>
                          {initials(u.display_name)}
                        </span>
                        <span style={styles.userText}>
                          <span style={styles.userName}>{u.display_name}</span>
                          <span style={styles.userEmail}>{u.email}</span>
                        </span>
                        <span style={styles.action}>
                          {pendingDemoId === u.id ? "Signing in…" : "Sign in →"}
                        </span>
                      </button>
                    ))}
                  </div>
                ))}
              </>
            )}
          </div>
        )}
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
  formSide: { display: "flex", flexDirection: "column", justifyContent: "center", padding: "60px 72px", background: "var(--paper)", overflowY: "auto" },
  brand: { display: "flex", alignItems: "center", gap: 13, marginBottom: 40 },
  brandLogo: {
    width: 44, height: 44, borderRadius: 12, display: "grid", placeItems: "center",
    background: "linear-gradient(135deg, var(--primary-dark), #786cff)", color: "#fff", fontWeight: 800, fontSize: 15,
  },
  brandName: { fontWeight: 700, fontSize: 17, color: "var(--ink)" },
  brandSub: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 2 },
  h1: { fontSize: 28, margin: "0 0 8px", letterSpacing: -0.6, color: "var(--ink)" },
  lead: { color: "var(--ink-soft)", fontSize: 13.5, lineHeight: 1.6, margin: "0 0 22px", maxWidth: 400 },
  ssoBtn: {
    width: "100%", height: 46, display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
    border: "1px solid var(--line)", borderRadius: 10, background: "var(--surface)", fontSize: 13.5, fontWeight: 600,
    color: "var(--ink)", marginBottom: 8, cursor: "pointer", textDecoration: "none", boxSizing: "border-box",
  },
  divider: {
    display: "flex", alignItems: "center", gap: 12, margin: "16px 0", color: "var(--ink-soft)",
    fontSize: 11.5, justifyContent: "center",
  },
  input: {
    width: "100%", height: 44, padding: "0 14px", marginBottom: 10, border: "1px solid var(--line)",
    borderRadius: 8, fontSize: 13.5, background: "var(--surface)", color: "var(--ink)", boxSizing: "border-box",
  },
  errorBox: {
    fontSize: 12.5, color: "var(--danger)", background: "var(--danger-soft)", borderRadius: 8, padding: "8px 12px", marginBottom: 12,
  },
  submitBtn: {
    width: "100%", height: 44, border: "none", borderRadius: 8, background: "var(--primary)", color: "#fff",
    fontSize: 14, fontWeight: 700, cursor: "pointer", marginTop: 4,
  },
  switchModeRow: { fontSize: 13, color: "var(--ink-soft)", textAlign: "center", marginTop: 16 },
  linkBtn: { background: "none", border: "none", color: "var(--primary)", fontWeight: 700, fontSize: "inherit", cursor: "pointer", padding: 0 },
  demoSection: { marginTop: 22, paddingTop: 18, borderTop: "1px solid var(--line)", textAlign: "center" },
  groupTitle: { fontSize: 12, fontWeight: 700, color: "var(--ink-soft)", marginBottom: 10, textAlign: "left" },
  groupLabel: {
    display: "flex", alignItems: "center", gap: 8, fontSize: 11, fontFamily: "var(--mono)", letterSpacing: 0.5,
    textTransform: "uppercase", color: "var(--ink-soft)", margin: "14px 0 7px", textAlign: "left",
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
