import { useMemo, useState } from "react";
import {
  BarChart, Bar, LineChart, Line, AreaChart, Area, PieChart, Pie, Cell,
  ScatterChart, Scatter, XAxis, YAxis, ZAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer,
} from "recharts";
import { ChatChartData } from "../lib/api";

const SERIES_COLORS = ["#252A5A", "#007C7A", "#3B82F6", "#F4B942", "#168A52", "#C77B00"];

type ChartKind = "table" | "cards" | "column" | "bar" | "line" | "area" | "pie" | "donut" | "scatter";

// Recharts' default YAxis width (60px) isn't enough for raw values like
// 19,487,022,237 — the tick labels were being silently clipped to
// nothing. Compact-formatting the labels (19.5B, 82.1M, 4.2K) fixes the
// clipping and is far more readable than the raw number anyway.
function formatCompact(value: number): string {
  return new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(value);
}

function formatFull(value: number | null): string {
  return value === null ? "N/A" : new Intl.NumberFormat("en").format(value);
}

interface Props {
  data: ChatChartData;
}

// Number("1,323,713,528.63") is NaN — plain Number() chokes on thousands
// separators, currency symbols, and surrounding whitespace, all of which
// commonly show up in query results. Without stripping these, a column
// like TotalPremium would silently fail the numeric check and get
// swept into the label instead of charted as the metric it actually is
// — exactly what produced a giant raw number inside an x-axis label.
function parseNumeric(value: unknown): number {
  if (typeof value === "number") return value;
  const cleaned = String(value).trim().replace(/[,$%\s]/g, "");
  return Number(cleaned);
}

function isNumeric(value: unknown): boolean {
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value !== "string" || value.trim() === "") return false;
  return !Number.isNaN(parseNumeric(value));
}

// Common placeholder text for "no value here" — not just genuine
// null/undefined/empty string. Query results routinely use "N/A", "-",
// or "—" for a metric that doesn't apply to a particular row (e.g. a
// ratio that couldn't be computed for one product line). Missing THIS
// check meant a single "N/A" cell disqualified an entire otherwise-
// numeric column from being charted as a metric — it fell into the
// label instead, which is exactly how a huge unrelated number ended up
// stuck onto the x-axis text.
const MISSING_TOKENS = new Set(["n/a", "na", "-", "—", "null", "none", "nil"]);

function isMissing(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value !== "string") return false;
  const trimmed = value.trim().toLowerCase();
  return trimmed === "" || MISSING_TOKENS.has(trimmed);
}

// ID/key columns (ClaimID, PolicyID, FactClaimID, customer_id, etc.) are
// numeric but are identifiers, not metrics — charting them produces a
// meaningless series (e.g. claim ID 53789 plotted next to a dollar
// amount). Excluded from charting regardless of naming convention.
function isIdentifierColumn(columnName: string): boolean {
  return /id$/i.test(columnName.trim());
}

// Year/Quarter/Month/Week/Period columns are numeric (2024, 1, 3...) but
// are a TIME DIMENSION, not a metric — they belong on the label, not as
// their own invisible sliver of a bar next to a dollar-amount series.
function isDimensionColumn(columnName: string): boolean {
  return isIdentifierColumn(columnName) || /(^|[^a-z])(year|quarter|qtr|month|week|period)/i.test(columnName);
}

// A column counts as numeric-by-value if every NON-MISSING cell parses
// as a number — one blank cell (e.g. a quarter with no loss ratio yet)
// no longer disqualifies the whole column.
function numericByValueIndexes(columns: string[], rows: any[][]): number[] {
  const idxs: number[] = [];
  for (let c = 0; c < columns.length; c++) {
    const present = rows.map((r) => r[c]).filter((v) => !isMissing(v));
    if (present.length > 0 && present.every(isNumeric)) idxs.push(c);
  }
  return idxs;
}

function formatDimensionValue(columnName: string, value: unknown): string {
  if (isMissing(value)) return "—";
  if (/(^|[^a-z])(quarter|qtr)/i.test(columnName)) return `Q${value}`;
  return String(value);
}

// ─────────────────────────── tiny inline icons ───────────────────────────
// No icon library in this project — these are small enough that adding a
// dependency for seven glyphs isn't worth it.
const ICONS: Record<ChartKind, JSX.Element> = {
  table: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="1.5" y="2.5" width="13" height="11" rx="1.2" />
      <line x1="1.5" y1="6" x2="14.5" y2="6" />
      <line x1="1.5" y1="9.5" x2="14.5" y2="9.5" />
      <line x1="6" y1="2.5" x2="6" y2="13.5" />
    </svg>
  ),
  cards: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="1.5" y="2.5" width="5.5" height="5" rx="1" />
      <rect x="9" y="2.5" width="5.5" height="5" rx="1" />
      <rect x="1.5" y="8.5" width="5.5" height="5" rx="1" />
      <rect x="9" y="8.5" width="5.5" height="5" rx="1" />
    </svg>
  ),
  column: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <line x1="1.5" y1="14" x2="14.5" y2="14" />
      <rect x="2.5" y="8" width="2.6" height="6" />
      <rect x="6.7" y="4.5" width="2.6" height="9.5" />
      <rect x="10.9" y="9.8" width="2.6" height="4.2" />
    </svg>
  ),
  bar: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <line x1="2" y1="1.5" x2="2" y2="14.5" />
      <rect x="2" y="2.5" width="9.5" height="2.6" />
      <rect x="2" y="6.7" width="6" height="2.6" />
      <rect x="2" y="10.9" width="11.2" height="2.6" />
    </svg>
  ),
  line: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <polyline points="1.5,12.5 5.5,7 9,10 14.5,3" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  ),
  area: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" stroke="none" opacity="0.9">
      <polygon points="1.5,14 1.5,12.5 5.5,7 9,10 14.5,3 14.5,14" opacity="0.35" />
      <polyline points="1.5,12.5 5.5,7 9,10 14.5,3" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  ),
  pie: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <circle cx="8" cy="8" r="6.2" />
      <path d="M8 1.8 A6.2 6.2 0 0 1 13.4 10.8 L8 8 Z" fill="currentColor" stroke="none" opacity="0.85" />
    </svg>
  ),
  donut: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.4">
      <circle cx="8" cy="8" r="6.2" />
      <path d="M8 1.8 A6.2 6.2 0 0 1 13.4 10.8 L8 8 Z" fill="currentColor" stroke="none" opacity="0.85" />
      <circle cx="8" cy="8" r="2.6" fill="#F8FAFC" stroke="none" />
    </svg>
  ),
  scatter: (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" stroke="none">
      <circle cx="3.2" cy="11.5" r="1.3" />
      <circle cx="7" cy="6.5" r="1.3" />
      <circle cx="10" cy="10" r="1.3" />
      <circle cx="12.8" cy="4" r="1.3" />
    </svg>
  ),
};

const LABELS: Record<ChartKind, string> = {
  table: "Table", cards: "Cards", column: "Column", bar: "Bar", line: "Line", area: "Area",
  pie: "Pie", donut: "Donut", scatter: "Scatter",
};

export default function ChatDataChart({ data }: Props) {
  const [chartType, setChartType] = useState<ChartKind | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);

  const built = useMemo(() => {
    const { columns, rows } = data;
    if (!columns.length || !rows.length) return null;

    const numericIdxs = numericByValueIndexes(columns, rows);
    if (numericIdxs.length === 0) return null; // nothing to plot — table only

    const dimensionIdxs = columns
      .map((name, i) => ({ name, i }))
      .filter(({ name, i }) => !numericIdxs.includes(i) || isDimensionColumn(name))
      .map(({ i }) => i);

    const seriesIdxs = numericIdxs.filter((i) => !dimensionIdxs.includes(i));
    if (seriesIdxs.length === 0) return null;

    const labelIdxs = dimensionIdxs.length > 0 ? dimensionIdxs : [0];

    const chartRows = rows.slice(0, 25).map((r) => {
      const label = labelIdxs.map((i) => formatDimensionValue(columns[i], r[i])).join(" ");
      const obj: Record<string, any> = { label };
      for (const i of seriesIdxs) obj[columns[i]] = isMissing(r[i]) ? null : parseNumeric(r[i]);
      return obj;
    });

    const isTimeLike = labelIdxs.some((i) => isDimensionColumn(columns[i]) && !isIdentifierColumn(columns[i]));
    const seriesNames = seriesIdxs.map((i) => columns[i]);

    // Which chart kinds actually make sense for THIS result — shown
    // options are filtered to this list rather than always offering
    // every kind regardless of whether the data supports it.
    const availableKinds: ChartKind[] = ["table", "cards", "column", "bar", "line", "area"];
    // Pie/donut need exactly one metric and a small, readable number of
    // slices — a 25-row pie chart is unreadable, and neither can show
    // more than one series at once (there's no second dimension for it).
    if (seriesNames.length === 1 && chartRows.length <= 8) availableKinds.push("pie", "donut");
    // Scatter needs two numeric metrics to plot against each other —
    // with only one series there's nothing to put on the other axis.
    if (seriesNames.length >= 2) availableKinds.push("scatter");

    // A single-row result (e.g. "which product line has the highest
    // loss ratio this year?" -> one row, several metrics) has nothing
    // meaningful to plot as a bar/line/pie — there's only one x-axis
    // category, or one pie slice per metric, neither of which reads as
    // a real chart. Cards are the right default here: one number per
    // metric, same as a KPI strip.
    const suggestedType: ChartKind = chartRows.length === 1 ? "cards" : isTimeLike ? "line" : "column";

    return { chartRows, seriesNames, suggestedType, availableKinds, columns, rows };
  }, [data]);

  if (!built) return null;
  const effectiveType = (chartType && built.availableKinds.includes(chartType)) ? chartType : built.suggestedType;

  function choose(kind: ChartKind) {
    setChartType(kind);
    setPickerOpen(false);
  }

  return (
    <div style={styles.wrap}>
      <div style={styles.header}>
        <span style={styles.title}>Chart</span>
        <div style={styles.pickerWrap}>
          {pickerOpen ? (
            <div style={styles.pickerRow}>
              {built.availableKinds.map((kind) => (
                <button
                  key={kind}
                  title={LABELS[kind]}
                  aria-label={LABELS[kind]}
                  style={{ ...styles.iconBtn, ...(effectiveType === kind ? styles.iconBtnActive : {}) }}
                  onClick={() => choose(kind)}
                >
                  {ICONS[kind]}
                </button>
              ))}
              <button title="Close" aria-label="Close chart type picker" style={styles.collapseBtn} onClick={() => setPickerOpen(false)}>
                ✕
              </button>
            </div>
          ) : (
            <button
              title={`Chart type: ${LABELS[effectiveType]} — click to change`}
              style={styles.currentBtn}
              onClick={() => setPickerOpen(true)}
            >
              {ICONS[effectiveType]}
              <span style={styles.chevron}>▾</span>
            </button>
          )}
        </div>
      </div>

      {effectiveType === "table" ? (
        <div style={styles.tableWrap}>
          <table style={styles.table}>
            <thead>
              <tr>{built.columns.map((c) => <th key={c} style={styles.th}>{c}</th>)}</tr>
            </thead>
            <tbody>
              {built.rows.slice(0, 25).map((row, i) => (
                <tr key={i}>{row.map((cell, j) => <td key={j} style={styles.td}>{cell ?? "—"}</td>)}</tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : effectiveType === "cards" ? (
        <div style={styles.cardsWrap}>
          {built.chartRows.map((row, i) => (
            <div key={i} style={styles.cardGroup}>
              {/* Only show the row's label as a group heading when there's
                  more than one row — for the single-row case (the whole
                  reason Cards exists) it would just repeat "Motor 2026"
                  above every metric card for no reason. */}
              {built.chartRows.length > 1 && <div style={styles.cardGroupLabel}>{row.label}</div>}
              <div style={styles.cardGrid}>
                {built.seriesNames.map((name, si) => {
                  const value = row[name];
                  return (
                    <div key={name} style={styles.metricCard}>
                      <div style={styles.metricLabel}>{name}</div>
                      <div style={{ ...styles.metricValue, color: SERIES_COLORS[si % SERIES_COLORS.length] }}>
                        {value === null ? "N/A" : formatCompact(value)}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={300}>
          {effectiveType === "column" ? (
            <BarChart data={built.chartRows} margin={{ top: 8, right: 12, left: 4, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E8EDF3" />
              <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#172033" }} interval={0} angle={-20} textAnchor="end" height={64} />
              <YAxis tick={{ fontSize: 12, fill: "#172033" }} width={64} tickFormatter={formatCompact} />
              <Tooltip formatter={formatFull} />
              {built.seriesNames.length > 1 && <Legend wrapperStyle={{ paddingTop: 12 }} />}
              {built.seriesNames.map((name, i) => (
                <Bar key={name} dataKey={name} fill={SERIES_COLORS[i % SERIES_COLORS.length]} radius={[3, 3, 0, 0]} />
              ))}
            </BarChart>
          ) : effectiveType === "bar" ? (
            <BarChart data={built.chartRows} layout="vertical" margin={{ top: 8, right: 16, left: 4, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E8EDF3" />
              <XAxis type="number" tick={{ fontSize: 12, fill: "#172033" }} tickFormatter={formatCompact} />
              <YAxis type="category" dataKey="label" tick={{ fontSize: 12, fill: "#172033" }} width={90} />
              <Tooltip formatter={formatFull} />
              {built.seriesNames.length > 1 && <Legend wrapperStyle={{ paddingTop: 12 }} />}
              {built.seriesNames.map((name, i) => (
                <Bar key={name} dataKey={name} fill={SERIES_COLORS[i % SERIES_COLORS.length]} radius={[0, 3, 3, 0]} />
              ))}
            </BarChart>
          ) : effectiveType === "line" ? (
            <LineChart data={built.chartRows} margin={{ top: 8, right: 12, left: 4, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E8EDF3" />
              <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#172033" }} interval={0} angle={-20} textAnchor="end" height={64} />
              <YAxis tick={{ fontSize: 12, fill: "#172033" }} width={64} tickFormatter={formatCompact} />
              <Tooltip formatter={formatFull} />
              {built.seriesNames.length > 1 && <Legend wrapperStyle={{ paddingTop: 12 }} />}
              {built.seriesNames.map((name, i) => (
                <Line key={name} type="monotone" dataKey={name} stroke={SERIES_COLORS[i % SERIES_COLORS.length]} strokeWidth={2} dot={{ r: 3 }} />
              ))}
            </LineChart>
          ) : effectiveType === "area" ? (
            <AreaChart data={built.chartRows} margin={{ top: 8, right: 12, left: 4, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E8EDF3" />
              <XAxis dataKey="label" tick={{ fontSize: 11, fill: "#172033" }} interval={0} angle={-20} textAnchor="end" height={64} />
              <YAxis tick={{ fontSize: 12, fill: "#172033" }} width={64} tickFormatter={formatCompact} />
              <Tooltip formatter={formatFull} />
              {built.seriesNames.length > 1 && <Legend wrapperStyle={{ paddingTop: 12 }} />}
              {built.seriesNames.map((name, i) => (
                <Area key={name} type="monotone" dataKey={name} stroke={SERIES_COLORS[i % SERIES_COLORS.length]} fill={SERIES_COLORS[i % SERIES_COLORS.length]} fillOpacity={0.25} strokeWidth={2} />
              ))}
            </AreaChart>
          ) : effectiveType === "pie" || effectiveType === "donut" ? (
            <PieChart margin={{ top: 8, right: 8, left: 8, bottom: 8 }}>
              <Tooltip formatter={formatFull} />
              <Legend />
              <Pie
                data={built.chartRows}
                dataKey={built.seriesNames[0]}
                nameKey="label"
                cx="50%"
                cy="50%"
                innerRadius={effectiveType === "donut" ? 55 : 0}
                outerRadius={90}
                label={(entry: any) => entry.label}
              >
                {built.chartRows.map((_, i) => (
                  <Cell key={i} fill={SERIES_COLORS[i % SERIES_COLORS.length]} />
                ))}
              </Pie>
            </PieChart>
          ) : (
            <ScatterChart margin={{ top: 8, right: 16, left: 4, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E8EDF3" />
              <XAxis
                type="number" dataKey={built.seriesNames[0]} name={built.seriesNames[0]}
                tick={{ fontSize: 12, fill: "#172033" }} tickFormatter={formatCompact}
              />
              <YAxis
                type="number" dataKey={built.seriesNames[1]} name={built.seriesNames[1]}
                tick={{ fontSize: 12, fill: "#172033" }} width={64} tickFormatter={formatCompact}
              />
              <ZAxis range={[60, 60]} />
              <Tooltip
                formatter={formatFull}
                labelFormatter={() => ""}
                cursor={{ strokeDasharray: "3 3" }}
              />
              <Scatter data={built.chartRows} fill={SERIES_COLORS[0]} />
            </ScatterChart>
          )}
        </ResponsiveContainer>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  wrap: {
    marginTop: 10,
    padding: "10px 12px 4px",
    background: "#F8FAFC",
    border: "1px solid #E8EDF3",
    borderRadius: 8,
  },
  header: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 4,
  },
  title: {
    fontSize: 12,
    fontWeight: 700,
    color: "#172033",
    textTransform: "uppercase",
    letterSpacing: 0.4,
  },
  pickerWrap: { display: "flex", justifyContent: "flex-end" },
  currentBtn: {
    display: "flex", alignItems: "center", gap: 3, padding: "3px 7px",
    borderRadius: 5, border: "1px solid #E8EDF3", background: "#fff", color: "#172033", cursor: "pointer",
  },
  chevron: { fontSize: 9, lineHeight: 1 },
  pickerRow: { display: "flex", alignItems: "center", gap: 3 },
  iconBtn: {
    display: "flex", alignItems: "center", justifyContent: "center",
    width: 24, height: 24, padding: 0,
    borderRadius: 5, border: "1px solid #E8EDF3", background: "#fff", color: "#172033", cursor: "pointer",
  },
  iconBtnActive: {
    background: "#252A5A",
    color: "#fff",
    borderColor: "#252A5A",
  },
  collapseBtn: {
    width: 20, height: 20, padding: 0, marginLeft: 2, fontSize: 10,
    borderRadius: 5, border: "1px solid transparent", background: "none", color: "#7A8699", cursor: "pointer",
  },
  tableWrap: { overflowX: "auto" },
  table: { width: "100%", borderCollapse: "collapse", fontSize: 12 },
  th: { textAlign: "left", padding: "6px 8px", background: "#EEF1F6", borderBottom: "1px solid #E8EDF3", fontWeight: 700, whiteSpace: "nowrap" },
  td: { padding: "6px 8px", borderBottom: "1px solid #E8EDF3", whiteSpace: "nowrap" },
  cardsWrap: { display: "flex", flexDirection: "column", gap: 12, paddingBottom: 6 },
  cardGroup: {},
  cardGroupLabel: { fontSize: 11.5, fontWeight: 700, color: "#172033", marginBottom: 6 },
  cardGrid: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: 8 },
  metricCard: {
    background: "#fff", border: "1px solid #E8EDF3", borderRadius: 8, padding: "10px 12px",
  },
  metricLabel: { fontSize: 10.5, color: "#7A8699", textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 4, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" },
  metricValue: { fontSize: 20, fontWeight: 700 },
};
