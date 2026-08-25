import { useState } from "react";

interface CardRow {
  k: string;
  v: string;
  color: string;
}

interface Card {
  label: string;
  labelColor: string;
  borderColor: string;
  rows: CardRow[];
  text: string;
}

interface Step {
  tab: "home" | "chat" | "genie" | "usecases" | "dashboards";
  eyebrow: string;
  headline: string;
  body: string;
  cards: [Card, Card];
}

const GREEN = "#4ade80";
const PURPLE = "#C78DFF";
const ORANGE = "#FF8533";
const WHITE = "#fff";

const STEPS: Step[] = [
  {
    tab: "home",
    eyebrow: "Step 1 of 5 · Overview",
    headline: "Role-based governed AI, on your Databricks investment.",
    body: "Every person who signs in lands here first — their role and permissions come straight from your tenant, not from anything typed into this app.",
    cards: [
      {
        label: "Databricks workspace", labelColor: GREEN, borderColor: "rgba(74,222,128,.25)",
        rows: [
          { k: "Delta Lake Gold", v: "connected", color: GREEN },
          { k: "Unity Catalog", v: "enforced", color: GREEN },
          { k: "Genie space", v: "governed", color: GREEN },
        ],
        text: "",
      },
      {
        label: "Ryze Infinity harness", labelColor: PURPLE, borderColor: "rgba(199,141,255,.25)",
        rows: [
          { k: "Roles", v: "role-aware", color: PURPLE },
          { k: "Guardrails", v: "active", color: PURPLE },
          { k: "Audit trail", v: "logging", color: PURPLE },
        ],
        text: "Your role and permissions come from your account — nothing typed here.",
      },
    ],
  },
  {
    tab: "chat",
    eyebrow: "Step 2 of 5 · Ask AI",
    headline: "A live governed query, no SQL required.",
    body: "Ask a plain-English question. The answer is grounded against your real Delta Lake Gold layer, with PII masked before the model ever sees it.",
    cards: [
      {
        label: "Live Delta Lake · Gold", labelColor: "#f87171", borderColor: "rgba(248,113,113,.2)",
        rows: [
          { k: "Source", v: "Unity Catalog view", color: WHITE },
          { k: "PII", v: "masked at source", color: GREEN },
          { k: "Access", v: "row-level ACL", color: WHITE },
        ],
        text: "The model never sees raw PII — only masked aggregates.",
      },
      {
        label: "Ryze Infinity analysis", labelColor: PURPLE, borderColor: "rgba(199,141,255,.2)",
        rows: [
          { k: "Grounding", v: "checked", color: GREEN },
          { k: "Confidence", v: "scored", color: PURPLE },
          { k: "Audit", v: "logged", color: WHITE },
        ],
        text: "Every answer is sourced and audit-logged, not just generated.",
      },
    ],
  },
  {
    tab: "genie",
    eyebrow: "Step 3 of 5 · Genie",
    headline: "Natural language to SQL, with Unity Catalog in the loop.",
    body: "Genie generates the SQL, queries your Gold layer, and returns live results — every query still passes through the same guardrail layer as Ask AI.",
    cards: [
      {
        label: "Genie · NL to SQL", labelColor: ORANGE, borderColor: "rgba(255,133,51,.25)",
        rows: [
          { k: "Input", v: "plain English", color: WHITE },
          { k: "Output", v: "live Delta SQL", color: ORANGE },
          { k: "ACL", v: "enforced", color: GREEN },
        ],
        text: "Databricks Genie Space — governed by Unity Catalog.",
      },
      {
        label: "Ryze Infinity layer", labelColor: PURPLE, borderColor: "rgba(199,141,255,.2)",
        rows: [
          { k: "Viz picker", v: "auto best-fit", color: PURPLE },
          { k: "Save insight", v: "to dashboard", color: WHITE },
          { k: "Guardrails", v: "same as Ask AI", color: WHITE },
        ],
        text: "Results render as a chart or table automatically.",
      },
    ],
  },
  {
    tab: "usecases",
    eyebrow: "Step 4 of 5 · Use cases",
    headline: "Preset analytical starting points for your industry.",
    body: "These aren't hardcoded — they're configured per tenant, so an insurance company and a bank see completely different presets.",
    cards: [
      {
        label: "Preset library", labelColor: GREEN, borderColor: "rgba(74,222,128,.2)",
        rows: [
          { k: "Source", v: "per-tenant config", color: GREEN },
          { k: "Coverage", v: "industry-specific", color: WHITE },
          { k: "Launch", v: "1-click question", color: WHITE },
        ],
        text: "Every company sees a different set of use cases.",
      },
      {
        label: "Ryze Infinity layer", labelColor: PURPLE, borderColor: "rgba(199,141,255,.2)",
        rows: [
          { k: "Preview", v: "before saving", color: PURPLE },
          { k: "Editable", v: "by admins", color: WHITE },
          { k: "Governed", v: "same guardrails", color: WHITE },
        ],
        text: "New presets can be tested before they go live for the team.",
      },
    ],
  },
  {
    tab: "dashboards",
    eyebrow: "Step 5 of 5 · Dashboards",
    headline: "Pin any result, from any tab.",
    body: "Text, charts, or tables — pin what matters straight from Ask AI, Genie, or a use case, and it lands here for later reference.",
    cards: [
      {
        label: "Saved insights", labelColor: GREEN, borderColor: "rgba(74,222,128,.2)",
        rows: [
          { k: "Source", v: "any tab", color: GREEN },
          { k: "Refresh", v: "on demand", color: WHITE },
          { k: "Layout", v: "resizable cards", color: WHITE },
        ],
        text: "",
      },
      {
        label: "Governance layer", labelColor: PURPLE, borderColor: "rgba(199,141,255,.2)",
        rows: [
          { k: "SQL", v: "visible per result", color: PURPLE },
          { k: "Guardrails", v: "logged", color: WHITE },
          { k: "HITL", v: "reviewable", color: "#fbbf24" },
        ],
        text: "Governed AI on your existing Databricks investment.",
      },
    ],
  },
];

interface Props {
  onStepChange: (tab: Step["tab"]) => void;
  onExit: () => void;
}

export default function GuidedDemoOverlay({ onStepChange, onExit }: Props) {
  const [step, setStep] = useState(0);
  const current = STEPS[step];

  function go(next: number) {
    setStep(next);
    onStepChange(STEPS[next].tab);
  }

  function handleNext() {
    if (step === STEPS.length - 1) onExit();
    else go(step + 1);
  }

  return (
    <div style={styles.overlay}>
      <div style={styles.card}>
        <div style={styles.header}>
          <div style={styles.dots}>
            {STEPS.map((_, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center" }}>
                <div style={{ ...styles.dot, ...(i === step ? styles.dotCurrent : i < step ? styles.dotDone : {}) }}>
                  {i + 1}
                </div>
                {i < STEPS.length - 1 && (
                  <span style={{ ...styles.connector, background: i < step ? "#7300E2" : "rgba(255,255,255,.1)" }} />
                )}
              </div>
            ))}
          </div>
          <div style={styles.title}>Guided demo</div>
          <button style={styles.exitBtn} onClick={onExit}>✕ Exit</button>
        </div>
        <div style={styles.progressTrack}>
          <div style={{ ...styles.progressFill, width: `${((step + 1) / STEPS.length) * 100}%` }} />
        </div>

        <div style={styles.body}>
          <div style={styles.stepEyebrow}>{current.eyebrow}</div>
          <div style={styles.headline}>{current.headline}</div>
          <div style={styles.text}>{current.body}</div>

          <div style={styles.cardGrid}>
            {current.cards.map((c, i) => (
              <div key={i} style={{ ...styles.infoCard, borderColor: c.borderColor }}>
                <div style={{ ...styles.infoCardLabel, color: c.labelColor }}>{c.label}</div>
                {c.rows.map((r) => (
                  <div key={r.k} style={styles.infoRow}>
                    <span style={styles.infoKey}>{r.k}</span>
                    <span style={{ ...styles.infoVal, color: r.color }}>{r.v}</span>
                  </div>
                ))}
                {c.text && <div style={styles.infoText}>{c.text}</div>}
              </div>
            ))}
          </div>
        </div>

        <div style={styles.footer}>
          <button
            style={{ ...styles.backBtn, ...(step === 0 ? styles.backBtnDisabled : {}) }}
            onClick={() => step > 0 && go(step - 1)}
            disabled={step === 0}
          >
            ← Back
          </button>
          <div style={styles.counter}>Step {step + 1} of {STEPS.length}</div>
          <button style={styles.nextBtn} onClick={handleNext}>
            {step === STEPS.length - 1 ? "Finish ✓" : "Next →"}
          </button>
        </div>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  overlay: {
    position: "fixed", inset: 0, zIndex: 500, background: "rgba(10,8,22,0.62)",
    display: "flex", alignItems: "center", justifyContent: "center", padding: 32,
  },
  card: {
    width: "100%", maxWidth: 920, background: "#0a0816", border: "1px solid rgba(199,141,255,0.2)",
    borderRadius: 12, overflow: "hidden", boxShadow: "0 32px 80px rgba(0,0,0,0.5)",
    fontFamily: "'Roboto', var(--sans, sans-serif)",
  },
  header: {
    background: "#2E0556", padding: "16px 22px", display: "flex", alignItems: "center",
    justifyContent: "space-between", borderBottom: "1px solid rgba(255,255,255,0.08)",
  },
  dots: { display: "flex", alignItems: "center" },
  dot: {
    width: 24, height: 24, borderRadius: "50%", display: "flex", alignItems: "center",
    justifyContent: "center", fontSize: 11, fontWeight: 700,
    background: "rgba(255,255,255,0.08)", color: "rgba(255,255,255,0.3)",
  },
  dotDone: { background: "#7300E2", color: "#fff" },
  dotCurrent: { background: "#7300E2", color: "#fff", outline: "2px solid #C78DFF", outlineOffset: 2 },
  connector: { width: 16, height: 1, margin: "0 5px" },
  title: { fontSize: 13, fontWeight: 600, color: "#fff" },
  exitBtn: {
    padding: "5px 13px", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 4,
    background: "rgba(255,255,255,0.07)", color: "rgba(255,255,255,0.6)", fontSize: 11, cursor: "pointer",
  },
  progressTrack: { height: 2, background: "rgba(255,255,255,0.07)" },
  progressFill: { height: "100%", background: "#7300E2", transition: "width 0.3s" },
  body: { padding: 24, minHeight: 300 },
  stepEyebrow: {
    fontSize: 11, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase",
    color: "#C78DFF", marginBottom: 8,
  },
  headline: { fontSize: 20, fontWeight: 900, letterSpacing: "-0.02em", color: "#fff", marginBottom: 8, lineHeight: 1.3 },
  text: { fontSize: 14, color: "rgba(255,255,255,0.65)", lineHeight: 1.65, maxWidth: "70ch", marginBottom: 18 },
  cardGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 },
  infoCard: {
    background: "rgba(255,255,255,0.04)", border: "1px solid", borderRadius: 8, padding: 16,
  },
  infoCardLabel: {
    fontSize: 10, fontWeight: 700, letterSpacing: "0.1em", textTransform: "uppercase", marginBottom: 10,
  },
  infoRow: {
    display: "flex", justifyContent: "space-between", alignItems: "center", padding: "6px 0",
    borderBottom: "1px solid rgba(255,255,255,0.06)", fontSize: 12,
  },
  infoKey: { color: "rgba(255,255,255,0.55)" },
  infoVal: { fontFamily: "var(--mono, monospace)", fontWeight: 600 },
  infoText: { fontSize: 12, color: "rgba(255,255,255,0.7)", lineHeight: 1.6, marginTop: 10 },
  footer: {
    background: "#2E0556", padding: "14px 22px", display: "flex", alignItems: "center",
    justifyContent: "space-between", borderTop: "1px solid rgba(255,255,255,0.08)",
  },
  backBtn: {
    padding: "8px 20px", border: "1px solid rgba(255,255,255,0.12)", borderRadius: 4,
    background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.6)", fontSize: 12, cursor: "pointer",
  },
  backBtnDisabled: { color: "rgba(255,255,255,0.25)", cursor: "default" },
  counter: { fontSize: 11, color: "rgba(255,255,255,0.4)" },
  nextBtn: {
    padding: "8px 24px", border: "none", borderRadius: 4, background: "#7300E2",
    color: "#fff", fontSize: 12, fontWeight: 700, cursor: "pointer",
  },
};
