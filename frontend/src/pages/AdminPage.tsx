import { useEffect, useState } from "react";
import { fetchCompanies, createCompany, createUser, Company, ApiError } from "../lib/api";

interface Props {
  token: string;
  sessionExpired: boolean;
  onSessionExpired: () => void;
}

export default function AdminPage({ token, sessionExpired, onSessionExpired }: Props) {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [companyName, setCompanyName] = useState("");
  const [industry, setIndustry] = useState("insurance");
  const [companyMsg, setCompanyMsg] = useState<string | null>(null);
  const [companyBusy, setCompanyBusy] = useState(false);

  const [userTenantId, setUserTenantId] = useState("");
  const [userName, setUserName] = useState("");
  const [userEmail, setUserEmail] = useState("");
  const [userMsg, setUserMsg] = useState<string | null>(null);
  const [userBusy, setUserBusy] = useState(false);

  function loadCompanies() {
    fetchCompanies(token)
      .then((list) => {
        setCompanies(list);
        if (!userTenantId && list.length > 0) setUserTenantId(list[0].id);
      })
      .catch((e: ApiError) => {
        if (e.status === 401) onSessionExpired();
        setLoadError(e.message);
      });
  }

  useEffect(loadCompanies, [token]);

  async function handleCreateCompany() {
    if (!companyName.trim() || companyBusy || sessionExpired) return;
    setCompanyBusy(true);
    setCompanyMsg(null);
    try {
      const c = await createCompany(token, companyName, industry);
      setCompanyMsg(`Created "${c.name}" — it now has a default Admin role with full access.`);
      setCompanyName("");
      loadCompanies();
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setCompanyMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setCompanyBusy(false);
    }
  }

  async function handleCreateUser() {
    if (!userName.trim() || !userEmail.trim() || !userTenantId || userBusy || sessionExpired) return;
    setUserBusy(true);
    setUserMsg(null);
    try {
      const u = await createUser(token, userTenantId, userName, userEmail);
      setUserMsg(`Created ${u.display_name} (${u.email}) — they can sign in immediately.`);
      setUserName("");
      setUserEmail("");
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onSessionExpired();
      setUserMsg(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setUserBusy(false);
    }
  }

  return (
    <div style={styles.page}>
      <div style={styles.noticeCard}>
        <strong>Platform Admin — testing convenience only.</strong>
      </div>

      {sessionExpired && (
        <div style={styles.expiredNote}>
          Your session has expired — sign in again (top right) to create companies or users.
        </div>
      )}

      <div style={styles.grid}>
        <section style={styles.card}>
          <div style={styles.cardTitle}>Add a company</div>
          <label style={styles.label}>Company name</label>
          <input
            style={styles.input}
            value={companyName}
            disabled={sessionExpired}
            onChange={(e) => setCompanyName(e.target.value)}
            placeholder="Enter your company name"
          />
          <label style={styles.label}>Industry</label>
          <select
            style={styles.input}
            value={industry}
            disabled={sessionExpired}
            onChange={(e) => setIndustry(e.target.value)}
          >
            <option value="insurance">Insurance</option>
            <option value="banking">Banking</option>
            <option value="healthcare">Healthcare</option>
            <option value="financial_services">Financial Services</option>
            <option value="retail">Retail</option>
          </select>
          <button
            style={styles.btn}
            onClick={handleCreateCompany}
            disabled={companyBusy || sessionExpired}
          >
            {companyBusy ? "Creating…" : "Create company"}
          </button>
          {companyMsg && <div style={styles.msg}>{companyMsg}</div>}
        </section>

        <section style={styles.card}>
          <div style={styles.cardTitle}>Add a user</div>
          <label style={styles.label}>Company</label>
          <select
            style={styles.input}
            value={userTenantId}
            disabled={sessionExpired}
            onChange={(e) => setUserTenantId(e.target.value)}
          >
            {companies.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <label style={styles.label}>Display name</label>
          <input
            style={styles.input}
            value={userName}
            disabled={sessionExpired}
            onChange={(e) => setUserName(e.target.value)}
            placeholder="Enter User's display name"
          />
          <label style={styles.label}>Email</label>
          <input
            style={styles.input}
            value={userEmail}
            disabled={sessionExpired}
            onChange={(e) => setUserEmail(e.target.value)}
            placeholder="Enter User's email address"
          />
          <button style={styles.btn} onClick={handleCreateUser} disabled={userBusy || sessionExpired}>
            {userBusy ? "Creating…" : "Create user"}
          </button>
          
          {userMsg && <div style={styles.msg}>{userMsg}</div>}
        </section>
      </div>

      <div style={styles.companyList}>
        <div style={styles.cardTitle}>Client's on this platform</div>
        {loadError && <div style={styles.msg}>{loadError}</div>}
        {companies.map((c) => (
          <div key={c.id} style={styles.companyRow}>
            <span style={{ fontWeight: 600 }}>{c.name}</span>
            <span style={{ color: "var(--ink-soft)" }}>{c.industry}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: { maxWidth: 900, margin: "0 auto", padding: "32px 24px 60px" },
  noticeCard: {
    background: "var(--paper)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 16,
    fontSize: 13,
    lineHeight: 1.6,
    color: "var(--ink-soft)",
    marginBottom: 20,
  },
  code: {
    fontFamily: "var(--mono)",
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 4,
    padding: "1px 5px",
  },
  expiredNote: {
    background: "#FFF7E6",
    border: "1px solid #F0C36D",
    borderRadius: 8,
    padding: "10px 14px",
    fontSize: 12.5,
    color: "#8A5A00",
    marginBottom: 20,
  },
  grid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 24 },
  card: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 18,
  },
  cardTitle: {
    fontSize: 11.5,
    fontFamily: "var(--mono)",
    letterSpacing: 0.5,
    textTransform: "uppercase",
    color: "var(--ink-soft)",
    marginBottom: 12,
  },
  label: { display: "block", fontSize: 12, fontWeight: 600, margin: "10px 0 5px" },
  input: {
    width: "100%",
    padding: "9px 11px",
    fontSize: 13.5,
    border: "1px solid var(--line)",
    borderRadius: 6,
    fontFamily: "var(--sans)",
    background: "var(--surface)",
    color: "var(--ink)",
  },
  btn: {
    marginTop: 14,
    width: "100%",
    padding: "10px 0",
    background: "var(--primary)",
    color: "white",
    border: "none",
    borderRadius: 6,
    fontWeight: 600,
    fontSize: 13.5,
    cursor: "pointer",
  },
  hint: { fontSize: 11.5, color: "var(--ink-soft)", marginTop: 8 },
  msg: { marginTop: 10, fontSize: 12.5, color: "var(--accent)", lineHeight: 1.5 },
  companyList: {
    background: "var(--surface)",
    border: "1px solid var(--line)",
    borderRadius: 10,
    padding: 18,
  },
  companyRow: {
    display: "flex",
    justifyContent: "space-between",
    fontSize: 13,
    padding: "8px 0",
    borderBottom: "1px solid var(--line)",
  },
};
