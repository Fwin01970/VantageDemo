import { useRef, useState } from "react";

type Dir = "n" | "s" | "e" | "w" | "ne" | "nw" | "se" | "sw";

interface Props {
  children: React.ReactNode;
  defaultWidth?: number;
  defaultHeight?: number;
  minWidth?: number;
  minHeight?: number;
  style?: React.CSSProperties;
}

// Native CSS `resize: both` only ever puts a handle on the bottom-right
// corner — there is no CSS-only way to resize from the top or left edge.
// This wraps a card with 8 invisible drag handles (4 edges + 4 corners)
// so it can be resized from any side, not just one corner.
export default function ResizableCard({
  children, defaultWidth = 380, defaultHeight = 340, minWidth = 300, minHeight = 220, style,
}: Props) {
  const [size, setSize] = useState({ width: defaultWidth, height: defaultHeight });
  const dragState = useRef<{ startX: number; startY: number; startW: number; startH: number; dir: Dir } | null>(null);

  function onPointerDown(e: React.PointerEvent, dir: Dir) {
    e.preventDefault();
    e.stopPropagation();
    dragState.current = { startX: e.clientX, startY: e.clientY, startW: size.width, startH: size.height, dir };
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp);
  }

  function onPointerMove(e: PointerEvent) {
    const d = dragState.current;
    if (!d) return;
    const dx = e.clientX - d.startX;
    const dy = e.clientY - d.startY;
    let width = d.startW;
    let height = d.startH;
    if (d.dir.includes("e")) width = d.startW + dx;
    if (d.dir.includes("w")) width = d.startW - dx;
    if (d.dir.includes("s")) height = d.startH + dy;
    if (d.dir.includes("n")) height = d.startH - dy;
    setSize({ width: Math.max(minWidth, width), height: Math.max(minHeight, height) });
  }

  function onPointerUp() {
    dragState.current = null;
    window.removeEventListener("pointermove", onPointerMove);
    window.removeEventListener("pointerup", onPointerUp);
  }

  const handles: { dir: Dir; style: React.CSSProperties }[] = [
    { dir: "n", style: { top: -3, left: 8, right: 8, height: 6, cursor: "ns-resize" } },
    { dir: "s", style: { bottom: -3, left: 8, right: 8, height: 6, cursor: "ns-resize" } },
    { dir: "e", style: { right: -3, top: 8, bottom: 8, width: 6, cursor: "ew-resize" } },
    { dir: "w", style: { left: -3, top: 8, bottom: 8, width: 6, cursor: "ew-resize" } },
    { dir: "ne", style: { top: -4, right: -4, width: 12, height: 12, cursor: "nesw-resize" } },
    { dir: "nw", style: { top: -4, left: -4, width: 12, height: 12, cursor: "nwse-resize" } },
    { dir: "se", style: { bottom: -4, right: -4, width: 12, height: 12, cursor: "nwse-resize" } },
    { dir: "sw", style: { bottom: -4, left: -4, width: 12, height: 12, cursor: "nesw-resize" } },
  ];

  return (
    <div style={{ position: "relative", width: size.width, height: size.height, maxWidth: "100%", ...style }}>
      {children}
      {handles.map((h) => (
        <div
          key={h.dir}
          onPointerDown={(e) => onPointerDown(e, h.dir)}
          style={{ position: "absolute", zIndex: 2, ...h.style }}
        />
      ))}
    </div>
  );
}
