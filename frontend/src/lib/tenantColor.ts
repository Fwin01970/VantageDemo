/**
 * Every tenant (company) gets a consistent, distinct accent color,
 * derived deterministically from its name — not random, and not
 * hardcoded per company. The same company always gets the same color,
 * and a brand-new company (added purely via database config, no code
 * change) automatically gets *some* color rather than none.
 *
 * This exists so that switching between demo users doesn't just say
 * "different tenant" in text — it visibly looks different, which is the
 * whole point of a multi-tenant demo.
 */
const PALETTE = ["#0f766e", "#7c4a2d", "#4338ca", "#a3462e", "#1d4ed8", "#65733f"];

export function tenantColor(tenantName: string): string {
  let hash = 0;
  for (let i = 0; i < tenantName.length; i++) {
    hash = (hash * 31 + tenantName.charCodeAt(i)) >>> 0;
  }
  return PALETTE[hash % PALETTE.length];
}

export function initials(name: string): string {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase())
    .join("");
}
