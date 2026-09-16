import { useEffect, useState } from "react";
import Dashboard from "../pages/Dashboard";
import ChatPage from "../pages/ChatPage";
import GeniePage from "../pages/GeniePage";
import DashboardPage from "../pages/DashboardPage";
import UseCasesPage from "../pages/UseCasesPage";
import { TenantsPage, UsersPage, AuditLogPage, QueryParametersPage, ManageTabsPage, ManageSchemaTablesPage } from "../pages/AdminPages";
import GovernancePanel from "./GovernancePanel";
import CredentialsModal from "./CredentialsModal";
import UserMenu from "./UserMenu";
import Footer from "./Footer";
import GuidedDemoOverlay from "./GuidedDemoOverlay";
import DemoPlaceholder from "./DemoPlaceholder";
import { GenieResult, MeResponse, fetchMe, ApiError } from "../lib/api";
import { getTheme, toggleTheme, Theme } from "../lib/theme";
import { tenantColor, initials } from "../lib/tenantColor";

interface Props {
  token: string;
  onLogout: () => void;
  // Present only when there's no real session — the app is being
  // explored with no login and no backend calls at all. "guided" also
  // drives the step-by-step overlay; "explore" just skips it.
  demoMode?: "guided" | "explore" | null;
  onRequestLogin?: () => void;
}

type Tab = "home" | "chat" | "genie" | "usecases" | "dashboards"
  | "admin-tenants" | "admin-users" | "admin-audit" | "admin-query-params" | "admin-manage-tabs" | "admin-schema-tables";

export default function AppShell({ token, onLogout, demoMode = null, onRequestLogin }: Props) {
  const [tab, setTab] = useState<Tab>("home");
  const [theme, setThemeState] = useState<Theme>(getTheme());
  const [governanceOpen, setGovernanceOpen] = useState(false);
  const [credentialsOpen, setCredentialsOpen] = useState(false);
  const [lastResult, setLastResult] = useState<GenieResult | null>(null);
  const [me, setMe] = useState<MeResponse | null>(null);
  const [sessionExpired, setSessionExpired] = useState(false);
  const [pendingQuestion, setPendingQuestion] = useState<string | null>(null);
  // Guided demo overlay dismisses itself on Finish/Exit but the person
  // can keep browsing in demo mode afterward — this tracks that
  // separately from demoMode itself, which stays "guided" the whole time.
  const [guidedDismissed, setGuidedDismissed] = useState(false);

  useEffect(() => {
    // No real session in demo mode — there's nothing to authenticate,
    // and calling /me with an empty token would just 401 and flip on
    // the "session expired" banner for no reason.
    if (demoMode) return;
    fetchMe(token)
      .then(setMe)
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) setSessionExpired(true);
      });
  }, [token, demoMode]);

  const canManagePlatform = !demoMode && (me?.permissions.includes("platform:manage") ?? false);
  // A Super Admin session is platform-operator tooling, not a business
  // user's workspace — it deliberately shows only Ask AI, Dashboard, and
  // Admin. Use Cases (tenant-specific preset business questions) has no
  // meaning for a Super Admin account, which doesn't belong to any real
  // customer tenant.
  const isSuperAdmin = canManagePlatform;
  // Genie's tab visibility normally follows the real permission — but
  // the guided demo walks through a Genie step regardless of role, so
  // demo mode always shows the tab (it just renders a locked
  // placeholder instead of doing anything with real data).
  const canUseGenie = demoMode ? true : (me?.permissions.includes("genie:access") ?? false);
  const demoTenantName = "ABC Insurance (Demo)";
  const demoIndustry = "insurance";
  const requestLogin = onRequestLogin ?? (() => {});

  function launchUseCase(question: string) {
    // No longer called from Use Cases (see UseCasesPage's own inline
    // runner) — kept as a small, reusable "jump to Ask AI with a
    // pre-filled question" helper in case another page wants the same
    // navigate-and-ask behavior later.
    setPendingQuestion(question);
    setTab("chat");
  }

  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <div style={styles.brand}>
          <div style={{ ...styles.brandMark, background: demoMode ? "#0F6E56" : me ? tenantColor(me.tenant_name) : "rgba(255,255,255,0.16)" }}>
            {demoMode ? "AI" : me ? initials(me.tenant_name) : "RI"}
          </div>
          <div>
            <div style={styles.brandName}>{demoMode ? demoTenantName : me?.tenant_name ?? "Ryze Infinity"}</div>
            <div style={styles.brandSub}>
              {demoMode
                ? "Insurance Intelligence · Powered by Ryze Infinity"
                : me
                ? `${me.industry.charAt(0).toUpperCase() + me.industry.slice(1)} Intelligence · Powered by Ryze Infinity`
                : "Enterprise Analytics Platform"}
            </div>
          </div>
        </div>

        <div style={styles.headerRight}>
          <button
            style={styles.themeBtn}
            onClick={() => setThemeState(toggleTheme())}
            title="Toggle dark mode"
            aria-label="Toggle dark mode"
          >
            {theme === "dark" ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
                <circle cx="12" cy="12" r="4.5" /><path d="M12 2v2M12 20v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2 12h2M20 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4" />
              </svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
                <path d="M20 14.5A8 8 0 1 1 9.5 4 6.5 6.5 0 0 0 20 14.5z" />
              </svg>
            )}
          </button>
          {!demoMode && (
            <button
              style={styles.governanceBtn}
              onClick={() => setGovernanceOpen(true)}
              title="Governance — SQL, guardrails, grounding, audit log (testing only)"
              aria-label="Open governance panel"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M12 2L4 5v6c0 5 3.4 9 8 11 4.6-2 8-6 8-11V5l-8-3z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" fill="none" />
              </svg>
            </button>
          )}
          {demoMode ? (
            <button style={styles.loginBtn} onClick={requestLogin}>Login</button>
          ) : me ? (
            <UserMenu
              displayName={me.display_name} role={me.roles[0] ?? "Member"} tenantName={me.tenant_name}
              onLogout={onLogout} onOpenCredentials={() => setCredentialsOpen(true)}
            />
          ) : (
            <button style={styles.logoutButton} onClick={onLogout}>Sign out</button>
          )}
        </div>
      </header>

      <nav className="rz-navbar" style={styles.navBar}>
        <button style={{ ...styles.navBtn, ...(tab === "home" ? styles.navBtnActive : {}) }} onClick={() => setTab("home")}>
          Home
        </button>
        <button style={{ ...styles.navBtn, ...(tab === "chat" ? styles.navBtnActive : {}) }} onClick={() => setTab("chat")}>
          Ask AI
        </button>
        {canUseGenie && (
          <button style={{ ...styles.navBtn, ...(tab === "genie" ? styles.navBtnActive : {}) }} onClick={() => setTab("genie")}>
            Genie
          </button>
        )}
        {!isSuperAdmin && (
          <button style={{ ...styles.navBtn, ...(tab === "usecases" ? styles.navBtnActive : {}) }} onClick={() => setTab("usecases")}>
            Use Cases
          </button>
        )}
        <button style={{ ...styles.navBtn, ...(tab === "dashboards" ? styles.navBtnActive : {}) }} onClick={() => setTab("dashboards")}>
          Dashboards
        </button>
        {canManagePlatform && (
          <>
            <button style={{ ...styles.navBtn, ...(tab === "admin-tenants" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-tenants")}>
              Tenants
            </button>
            <button style={{ ...styles.navBtn, ...(tab === "admin-users" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-users")}>
              Users
            </button>
            <button style={{ ...styles.navBtn, ...(tab === "admin-query-params" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-query-params")}>
              Query Parameters
            </button>
            <button style={{ ...styles.navBtn, ...(tab === "admin-manage-tabs" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-manage-tabs")}>
              Manage Tabs
            </button>
            <button style={{ ...styles.navBtn, ...(tab === "admin-schema-tables" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-schema-tables")}>
              Manage Schema &amp; Tables
            </button>
            <button style={{ ...styles.navBtn, ...(tab === "admin-audit" ? styles.navBtnActive : {}) }} onClick={() => setTab("admin-audit")}>
              Audit Log
            </button>
          </>
        )}
      </nav>

      {sessionExpired && (
        <div style={styles.expiredBanner}>
          <span>
            Your session has expired. You can still view what's already on this
            page, but you'll need to sign in again to ask new questions or use Admin.
          </span>
          <button style={styles.expiredBtn} onClick={onLogout}>Sign in again</button>
        </div>
      )}

      <div style={styles.content}>
        {/* Keep-alive tabs: every tab stays MOUNTED (not conditionally
            rendered) so React state and in-flight requests survive
            switching away and back — e.g. asking a question in Ask AI,
            then checking Genie, no longer loses the eventual answer.
            display:"contents" makes the wrapper invisible to the flex
            layout (so ChatPage's own flex classes still work as if it
            were a direct child of .content); display:"none" hides a
            tab's DOM/visuals entirely while its component instance and
            state stay alive underneath. */}
        <div style={{ display: tab === "home" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0 }}>
          {demoMode ? (
            <DemoPlaceholder
              title="Home"
              description="This is where your role, permissions, and company are shown once you're signed in — pulled automatically from your account, nothing typed by you. Sign in to see your own."
              onLoginClick={requestLogin}
            />
          ) : (
            <Dashboard token={token} onLogout={onLogout} />
          )}
        </div>
        <div style={{ display: tab === "chat" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0 }}>
          {demoMode ? (
            <DemoPlaceholder
              title="Ask AI"
              description="Ask a plain-English question and get an answer grounded in your real data — with PII masking, guardrails, and a full audit trail. This needs a real session to actually query anything."
              onLoginClick={requestLogin}
            />
          ) : (
            <ChatPage
              token={token}
              sessionExpired={sessionExpired}
              onSessionExpired={() => setSessionExpired(true)}
              pendingQuestion={pendingQuestion}
              onPendingQuestionConsumed={() => setPendingQuestion(null)}
              onResult={setLastResult}
            />
          )}
        </div>
        {canUseGenie && (
          <div style={{ display: tab === "genie" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0 }}>
            {demoMode ? (
              <DemoPlaceholder
                title="Genie"
                description="Genie turns natural language into governed SQL against your Gold layer. Sign in to run a real query."
                onLoginClick={requestLogin}
              />
            ) : (
              <GeniePage
                token={token}
                onResult={setLastResult}
                sessionExpired={sessionExpired}
                onSessionExpired={() => setSessionExpired(true)}
              />
            )}
          </div>
        )}
        <div style={{ display: tab === "usecases" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0 }}>
          {demoMode ? (
            <DemoPlaceholder
              title="Use cases"
              description="Preset analytical starting points, configured per tenant and industry. Sign in to see the ones set up for your company."
              onLoginClick={requestLogin}
            />
          ) : (
            <UseCasesPage
              token={token}
              canCreate={true}
              onSessionExpired={() => setSessionExpired(true)}
              onResult={setLastResult}
            />
          )}
        </div>
        <div style={{ display: tab === "dashboards" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0 }}>
          {demoMode ? (
            <DemoPlaceholder
              title="Dashboards"
              description="Pin any result from Ask AI, Genie, or a use case, and it shows up here. Sign in to start pinning your own."
              onLoginClick={requestLogin}
            />
          ) : (
            <DashboardPage token={token} onSessionExpired={() => setSessionExpired(true)} />
          )}
        </div>
        {canManagePlatform && (
          <>
            <div style={{ display: tab === "admin-tenants" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <TenantsPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
            <div style={{ display: tab === "admin-users" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <UsersPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
            <div style={{ display: tab === "admin-audit" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <AuditLogPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
            <div style={{ display: tab === "admin-query-params" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <QueryParametersPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
            <div style={{ display: tab === "admin-manage-tabs" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <ManageTabsPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
            <div style={{ display: tab === "admin-schema-tables" ? "flex" : "none", flexDirection: "column", flex: 1, minHeight: 0, overflowY: "auto" }}>
              <ManageSchemaTablesPage token={token} sessionExpired={sessionExpired} onSessionExpired={() => setSessionExpired(true)} />
            </div>
          </>
        )}
      </div>

      {demoMode ? (
        <Footer tenantName={demoTenantName} industry={demoIndustry} />
      ) : (
        me && <Footer tenantName={me.tenant_name} industry={me.industry} />
      )}

      {governanceOpen && (
        <GovernancePanel
          token={token}
          lastResult={lastResult}
          onClose={() => setGovernanceOpen(false)}
          onSessionExpired={() => setSessionExpired(true)}
        />
      )}

      {credentialsOpen && (
        <CredentialsModal token={token} onClose={() => setCredentialsOpen(false)} />
      )}

      {demoMode === "guided" && !guidedDismissed && (
        <GuidedDemoOverlay
          onStepChange={(t) => setTab(t)}
          onExit={() => setGuidedDismissed(true)}
        />
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { height: "100vh", display: "flex", flexDirection: "column" },
  header: {
    display: "flex", alignItems: "center", justifyContent: "space-between",
    padding: "0 24px", height: 64, color: "#fff",
    background: "radial-gradient(circle at 18% -100%, rgba(255,255,255,0.25), transparent 42%), linear-gradient(115deg, #2c2470, var(--primary) 58%, #786cff)",
    boxShadow: "0 3px 16px rgba(39,30,105,0.25)", position: "sticky", top: 0, zIndex: 50,
  },
  brand: { display: "flex", alignItems: "center", gap: 12 },
  brandMark: {
    width: 38, height: 38, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center",
    border: "1px solid rgba(255,255,255,0.35)", background: "rgba(255,255,255,0.16)", fontWeight: 800, fontSize: 13,
  },
  brandName: { fontWeight: 700, fontSize: 15.5, letterSpacing: -0.2 },
  brandSub: { fontSize: 10.5, color: "rgba(255,255,255,0.72)", marginTop: 1 },
  headerRight: { display: "flex", alignItems: "center", gap: 10 },
  navBar: {
    display: "flex", gap: 4, padding: "0 24px", background: "var(--surface)",
    borderBottom: "1px solid var(--line)", position: "sticky", top: 64, zIndex: 40,
  },
  navBtn: {
    background: "none", border: "none", borderBottom: "3px solid transparent", padding: "13px 16px", fontSize: 13,
    fontWeight: 600, color: "var(--ink-soft)", cursor: "pointer",
  },
  navBtnActive: {
    color: "var(--primary)", borderBottom: "3px solid var(--primary)",
    background: "linear-gradient(to top, var(--primary-soft), transparent 70%)",
  },
  governanceBtn: {
    background: "rgba(255,255,255,0.12)", border: "1px solid rgba(255,255,255,0.28)", borderRadius: 8, width: 34, height: 34,
    cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff",
  },
  themeBtn: {
    background: "rgba(255,255,255,0.12)", border: "1px solid rgba(255,255,255,0.28)", borderRadius: 8, width: 34, height: 34,
    cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff",
  },
  logoutButton: {
    background: "rgba(255,255,255,0.12)", border: "1px solid rgba(255,255,255,0.28)", borderRadius: 8, padding: "8px 14px",
    fontSize: 13, fontWeight: 600, color: "#fff", cursor: "pointer",
  },
  loginBtn: {
    background: "#fff", border: "none", borderRadius: 8, padding: "8px 18px",
    fontSize: 13, fontWeight: 700, color: "var(--primary)", cursor: "pointer",
  },
  expiredBanner: {
    display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16,
    background: "#FFF7E6", borderBottom: "1px solid #F0C36D", color: "#8A5A00", padding: "10px 24px", fontSize: 13,
  },
  expiredBtn: {
    background: "#8A5A00", color: "white", border: "none", borderRadius: 6, padding: "6px 14px",
    fontSize: 12.5, fontWeight: 600, cursor: "pointer", whiteSpace: "nowrap",
  },
  content: { flex: 1, minHeight: 0, display: "flex", flexDirection: "column" },
};
