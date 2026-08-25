import React from "react";

// A small, dependency-free markdown renderer covering exactly what the
// Ask AI assistant actually produces: headings (#/##/###), bold (**text**),
// bullet lists (-/*), numbered lists, fenced code blocks (```), and
// GitHub-style pipe tables. Not a general-purpose markdown engine — just
// enough to turn the model's raw markdown into readable, structured HTML
// instead of showing asterisks and pipes literally in the chat bubble.

function renderInline(text: string, keyPrefix: string): React.ReactNode[] {
  const parts: React.ReactNode[] = [];
  const regex = /\*\*(.+?)\*\*|`([^`]+)`/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  let i = 0;
  while ((match = regex.exec(text)) !== null) {
    if (match.index > lastIndex) parts.push(text.slice(lastIndex, match.index));
    if (match[1] !== undefined) {
      parts.push(<strong key={`${keyPrefix}-b-${i++}`}>{match[1]}</strong>);
    } else if (match[2] !== undefined) {
      parts.push(
        <code key={`${keyPrefix}-c-${i++}`} style={styles.inlineCode}>
          {match[2]}
        </code>
      );
    }
    lastIndex = regex.lastIndex;
  }
  if (lastIndex < text.length) parts.push(text.slice(lastIndex));
  return parts;
}

function parseTable(lines: string[], startIdx: number): { node: React.ReactNode; nextIdx: number } | null {
  const headerLine = lines[startIdx];
  const sepLine = lines[startIdx + 1];
  if (!headerLine?.includes("|") || !sepLine || !/^[\s|:-]+$/.test(sepLine)) return null;

  const splitRow = (line: string) =>
    line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());

  const headers = splitRow(headerLine);
  const rows: string[][] = [];
  let idx = startIdx + 2;
  while (idx < lines.length && lines[idx].includes("|")) {
    rows.push(splitRow(lines[idx]));
    idx++;
  }

  return {
    node: (
      <div key={`table-${startIdx}`} style={styles.tableWrap}>
        <table style={styles.table}>
          <thead>
            <tr>
              {headers.map((h, i) => (
                <th key={i} style={styles.th}>
                  {renderInline(h, `th-${startIdx}-${i}`)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, r) => (
              <tr key={r}>
                {row.map((cell, c) => (
                  <td key={c} style={styles.td}>
                    {renderInline(cell, `td-${startIdx}-${r}-${c}`)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    ),
    nextIdx: idx,
  };
}

export default function MarkdownLite({ text }: { text: string }) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const blocks: React.ReactNode[] = [];
  let i = 0;
  let listBuffer: { ordered: boolean; items: string[] } | null = null;

  function flushList() {
    if (!listBuffer) return;
    const Tag = listBuffer.ordered ? "ol" : "ul";
    blocks.push(
      <Tag key={`list-${blocks.length}`} style={styles.list}>
        {listBuffer.items.map((item, idx) => (
          <li key={idx} style={styles.listItem}>
            {renderInline(item, `li-${blocks.length}-${idx}`)}
          </li>
        ))}
      </Tag>
    );
    listBuffer = null;
  }

  while (i < lines.length) {
    const line = lines[i];

    if (line.trim() === "") {
      flushList();
      i++;
      continue;
    }

    // Fenced code block
    if (line.trim().startsWith("```")) {
      flushList();
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith("```")) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing fence
      blocks.push(
        <pre key={`code-${i}`} style={styles.codeBlock}>
          <code>{codeLines.join("\n")}</code>
        </pre>
      );
      continue;
    }

    // Table
    const table = parseTable(lines, i);
    if (table) {
      flushList();
      blocks.push(table.node);
      i = table.nextIdx;
      continue;
    }

    // Headings
    const headingMatch = /^(#{1,4})\s+(.*)$/.exec(line);
    if (headingMatch) {
      flushList();
      const level = headingMatch[1].length;
      const HeadingTag = (`h${Math.min(level + 3, 6)}` as unknown) as keyof JSX.IntrinsicElements;
      blocks.push(
        <HeadingTag key={`h-${i}`} style={styles.heading}>
          {renderInline(headingMatch[2], `h-${i}`)}
        </HeadingTag>
      );
      i++;
      continue;
    }

    // Horizontal rule
    if (/^-{3,}$/.test(line.trim())) {
      flushList();
      blocks.push(<hr key={`hr-${i}`} style={styles.hr} />);
      i++;
      continue;
    }

    // Bullet / numbered list items
    const bulletMatch = /^[-*]\s+(.*)$/.exec(line);
    const numberedMatch = /^\d+\.\s+(.*)$/.exec(line);
    if (bulletMatch || numberedMatch) {
      const ordered = !!numberedMatch;
      const content = (bulletMatch || numberedMatch)![1];
      if (!listBuffer || listBuffer.ordered !== ordered) {
        flushList();
        listBuffer = { ordered, items: [] };
      }
      listBuffer.items.push(content);
      i++;
      continue;
    }

    // Plain paragraph
    flushList();
    blocks.push(
      <p key={`p-${i}`} style={styles.paragraph}>
        {renderInline(line, `p-${i}`)}
      </p>
    );
    i++;
  }
  flushList();

  return <div style={styles.wrap}>{blocks}</div>;
}

const styles: Record<string, React.CSSProperties> = {
  wrap: { display: "flex", flexDirection: "column", gap: 6 },
  paragraph: { margin: 0, whiteSpace: "pre-wrap" },
  heading: { margin: "4px 0 2px", fontWeight: 700 },
  hr: { border: "none", borderTop: "1px solid var(--line)", margin: "4px 0" },
  list: { margin: "2px 0", paddingLeft: 20 },
  listItem: { marginBottom: 2 },
  inlineCode: {
    fontFamily: "var(--mono)", background: "var(--paper)", borderRadius: 4,
    padding: "1px 5px", fontSize: "0.92em",
  },
  codeBlock: {
    fontFamily: "var(--mono)", background: "var(--paper)", border: "1px solid var(--line)",
    borderRadius: 6, padding: "8px 10px", fontSize: 12, overflowX: "auto", margin: 0,
  },
  tableWrap: { overflowX: "auto" },
  table: { width: "100%", borderCollapse: "collapse", fontSize: "0.92em" },
  th: {
    textAlign: "left", padding: "6px 8px", background: "var(--paper)",
    borderBottom: "1px solid var(--line)", whiteSpace: "nowrap",
  },
  td: { padding: "6px 8px", borderBottom: "1px solid var(--line)" },
};
