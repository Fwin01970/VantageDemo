import { useEffect, useRef, useState } from "react";
import { tenantColor, initials } from "../lib/tenantColor";

interface Props {
  displayName: string;
  role: string;
  tenantName: string;
  onLogout: () => void;
  onOpenCredentials: () => void;
}

export default function UserMenu({ displayName, role, tenantName, onLogout, onOpenCredentials }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  const color = tenantColor(tenantName);

  return (
    <div ref={ref} style={styles.wrap}>
      <button style={styles.trigger} onClick={() => setOpen((o) => !o)} aria-haspopup="menu" aria-expanded={open}>
        <span style={{ ...styles.avatar, background: color }}>{initials(displayName)}</span>
        <span style={styles.textBlock}>
          <span style={styles.name}>{displayName}</span>
          <span style={styles.role}>{role}</span>
        </span>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      {open && (
        <div style={styles.menu} role="menu">
          <div style={styles.menuHeader}>Signed in to <strong>{tenantName}</strong></div>
          <button style={styles.menuItem} onClick={() => setOpen(false)}>
            Profile <span style={styles.soon}>Coming soon</span>
          </button>
          <button style={styles.menuItem} onClick={() => setOpen(false)}>
            Account settings <span style={styles.soon}>Coming soon</span>
          </button>
          <button style={styles.menuItem} onClick={() => { setOpen(false); onOpenCredentials(); }}>
            Credentials
          </button>
          <div style={styles.divider} />
          <button style={{ ...styles.menuItem, color: "var(--danger)" }} onClick={onLogout}>
            Sign out
          </button>
        </div>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  wrap: { position: "relative" },
  trigger: {
    display: "flex", alignItems: "center", gap: 9, background: "rgba(255,255,255,0.12)",
    border: "1px solid rgba(255,255,255,0.28)", borderRadius: 10, padding: "6px 10px 6px 6px",
    cursor: "pointer", color: "#fff",
  },
  avatar: {
    width: 30, height: 30, borderRadius: 8, color: "#fff", fontSize: 11.5, fontWeight: 700,
    display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
  },
  textBlock: { display: "flex", flexDirection: "column", alignItems: "flex-start" },
  name: { fontSize: 12.5, fontWeight: 600, lineHeight: 1.2 },
  role: { fontSize: 10, color: "rgba(255,255,255,0.72)", lineHeight: 1.2 },
  menu: {
    position: "absolute", right: 0, top: "calc(100% + 8px)", width: 230, background: "var(--surface)",
    border: "1px solid var(--line)", borderRadius: 10, boxShadow: "var(--shadow)", zIndex: 60, overflow: "hidden",
  },
  menuHeader: {
    padding: "10px 14px", fontSize: 11.5, color: "var(--ink-soft)", borderBottom: "1px solid var(--line)",
  },
  menuItem: {
    width: "100%", textAlign: "left", background: "none", border: "none", padding: "10px 14px", fontSize: 13,
    color: "var(--ink)", cursor: "pointer", display: "flex", justifyContent: "space-between", alignItems: "center",
  },
  soon: { fontSize: 9.5, color: "var(--ink-soft)", fontStyle: "italic" },
  divider: { height: 1, background: "var(--line)" },
};
