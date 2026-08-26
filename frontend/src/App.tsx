import { useEffect, useState } from "react";
import Login from "./pages/Login";
import SplashPage from "./pages/SplashPage";
import AppShell from "./components/AppShell";
import IdleWarningModal from "./components/IdleWarningModal";
import { useIdleLogout } from "./lib/useIdleLogout";

// Storing the token in localStorage is fine here — this is a real app
// running on your own machine, not a hosted/shared environment — it just
// means refreshing the page keeps you signed in instead of logging you
// out every time. This whole mechanism gets replaced by Microsoft's own
// sign-in session handling once real Entra ID is wired in.
const STORAGE_KEY = "ryze_infinity_token";

type View = "splash" | "login" | "app";
type DemoMode = "guided" | "explore" | null;

function tokenFromUrl(): string | null {
  // OAuth callbacks (routers/auth.py) redirect to "/?token=...&" after a
  // successful sign-in — this is how that token actually reaches the
  // React app. Reads once on load, then strips it from the URL so a
  // page refresh or shared link never re-exposes it in browser history.
  const params = new URLSearchParams(window.location.search);
  const token = params.get("token");
  if (token) {
    params.delete("token");
    const rest = params.toString();
    window.history.replaceState({}, "", window.location.pathname + (rest ? `?${rest}` : ""));
  }
  return token;
}

export default function App() {
  const [token, setToken] = useState<string | null>(() => {
    const fromUrl = tokenFromUrl();
    if (fromUrl) {
      localStorage.setItem(STORAGE_KEY, fromUrl);
      return fromUrl;
    }
    return localStorage.getItem(STORAGE_KEY);
  });
  // A returning, already-authenticated user skips the splash entirely —
  // it only exists as an on-ramp for people who aren't signed in yet.
  const [view, setView] = useState<View>(token ? "app" : "splash");
  const [demoMode, setDemoMode] = useState<DemoMode>(null);

  function handleLoggedIn(newToken: string) {
    localStorage.setItem(STORAGE_KEY, newToken);
    setToken(newToken);
    setDemoMode(null);
    setView("app");
  }

  function handleLogout() {
    localStorage.removeItem(STORAGE_KEY);
    setToken(null);
    setDemoMode(null);
    setView("login");
  }

  function startDemo(mode: "guided" | "explore") {
    setDemoMode(mode);
    setView("app");
  }

  // Demo mode's "Login" button (in the header, or inside a locked-tab
  // placeholder) — drops out of demo mode and shows the REAL login
  // screen, same one an already-registered user would use directly.
  function requestLogin() {
    setDemoMode(null);
    setView("login");
  }

  // Auto-logout after inactivity — separate from the JWT's own fixed
  // 60-minute absolute expiry (auth/tokens.py). Only active for a real
  // signed-in session; demo mode has nothing to log out of.
  const { warning, stayActive } = useIdleLogout({
    idleMinutes: 30,
    warnBeforeMinutes: 2,
    enabled: !!token && view === "app" && !demoMode,
    onIdleLogout: handleLogout,
  });

  useEffect(() => {
    if (token && view !== "app") setView("app");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  if (view === "splash") {
    return (
      <SplashPage
        onStartGuided={() => startDemo("guided")}
        onExploreFree={() => startDemo("explore")}
      />
    );
  }

  if (view === "login" || (!token && view === "app" && !demoMode)) {
    return <Login onLoggedIn={handleLoggedIn} />;
  }

  // view === "app": either a real authenticated session, or demo mode
  // with no token at all — AppShell itself branches on demoMode to skip
  // real API calls and show the Login button instead of a user chip.
  return (
    <>
      <AppShell
        token={token ?? ""}
        onLogout={handleLogout}
        demoMode={demoMode}
        onRequestLogin={requestLogin}
      />
      {warning && <IdleWarningModal onStayActive={stayActive} />}
    </>
  );
}
