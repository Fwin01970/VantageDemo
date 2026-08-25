import { useState } from "react";
import Login from "./pages/Login";
import SplashPage from "./pages/SplashPage";
import AppShell from "./components/AppShell";

// Storing the token in localStorage is fine here — this is a real app
// running on your own machine, not a hosted/shared environment — it just
// means refreshing the page keeps you signed in instead of logging you
// out every time. This whole mechanism gets replaced by Microsoft's own
// sign-in session handling once real Entra ID is wired in.
const STORAGE_KEY = "ryze_infinity_token";

type View = "splash" | "login" | "app";
type DemoMode = "guided" | "explore" | null;

export default function App() {
  const [token, setToken] = useState<string | null>(() =>
    localStorage.getItem(STORAGE_KEY)
  );
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
    setView("splash");
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
    <AppShell
      token={token ?? ""}
      onLogout={handleLogout}
      demoMode={demoMode}
      onRequestLogin={requestLogin}
    />
  );
}
