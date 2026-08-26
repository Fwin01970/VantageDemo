import { useEffect, useRef, useState } from "react";

const ACTIVITY_EVENTS = ["mousedown", "mousemove", "keydown", "scroll", "touchstart", "click"];

interface Options {
  // Total idle time before logout fires.
  idleMinutes?: number;
  // How long before the deadline to show a "still there?" warning —
  // any activity during the warning window cancels the logout.
  warnBeforeMinutes?: number;
  enabled: boolean;
  onIdleLogout: () => void;
}

/**
 * Fully client-side — the backend's JWT already has its own fixed 60-
 * minute absolute expiry (auth/tokens.py), which doesn't care whether
 * the person is active. This adds the OTHER half real apps expect:
 * logging someone out after a period of INACTIVITY, even if their token
 * would otherwise still be valid — e.g. they stepped away from their
 * desk with the tab open.
 */
export function useIdleLogout({ idleMinutes = 30, warnBeforeMinutes = 2, enabled, onIdleLogout }: Options) {
  const [warning, setWarning] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const warnTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  function clearTimers() {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    if (warnTimeoutRef.current) clearTimeout(warnTimeoutRef.current);
  }

  function resetTimer() {
    clearTimers();
    setWarning(false);
    if (!enabled) return;
    const warnAfterMs = Math.max(0, (idleMinutes - warnBeforeMinutes) * 60_000);
    warnTimeoutRef.current = setTimeout(() => setWarning(true), warnAfterMs);
    timeoutRef.current = setTimeout(onIdleLogout, idleMinutes * 60_000);
  }

  useEffect(() => {
    if (!enabled) {
      clearTimers();
      setWarning(false);
      return;
    }
    resetTimer();
    const handler = () => resetTimer();
    ACTIVITY_EVENTS.forEach((evt) => window.addEventListener(evt, handler, { passive: true }));
    return () => {
      clearTimers();
      ACTIVITY_EVENTS.forEach((evt) => window.removeEventListener(evt, handler));
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, idleMinutes, warnBeforeMinutes]);

  return {
    warning,
    stayActive: resetTimer,
  };
}
