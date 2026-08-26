// A plain .slice(0, N) cuts mid-word with no indication anything was
// truncated — e.g. "...for the current year in our records (*" — which
// reads as broken, not shortened. This backs up to the last full word
// within the limit and appends "…" so a truncated title is visibly and
// legibly a summary, not a glitch.
export function truncateTitle(text: string, maxLength = 80): string {
  const trimmed = text.trim();
  if (trimmed.length <= maxLength) return trimmed;
  const cut = trimmed.slice(0, maxLength);
  const lastSpace = cut.lastIndexOf(" ");
  const safeCut = lastSpace > maxLength * 0.6 ? cut.slice(0, lastSpace) : cut;
  return safeCut.trimEnd() + "…";
}
