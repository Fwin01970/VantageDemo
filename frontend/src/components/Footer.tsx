interface Props {
  tenantName: string;
  industry: string;
}

export default function Footer({ tenantName, industry }: Props) {
  return (
    <footer style={styles.footer}>
      <div>
        <strong style={styles.name}>{tenantName}</strong>
        <span style={styles.tagline}> · {industry.charAt(0).toUpperCase() + industry.slice(1)} Intelligence · Powered by Ryze Infinity</span>
      </div>
      <div style={styles.right}>© {new Date().getFullYear()} Fulcrum Digital</div>
    </footer>
  );
}

const styles: Record<string, React.CSSProperties> = {
  footer: {
    display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center", justifyContent: "space-between",
    padding: "14px 24px", borderTop: "1px solid var(--line)", background: "var(--surface)",
    color: "var(--ink-soft)", fontSize: 11,
  },
  name: { color: "var(--ink)" },
  tagline: { color: "var(--ink-soft)" },
  right: { color: "var(--ink-soft)" },
};
