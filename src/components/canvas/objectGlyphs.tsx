import { useId } from 'react';
import type { ObjectLibraryEntry } from '../../domain/objectLibrary';

interface GlyphProps {
  entry: ObjectLibraryEntry;
  width: number;
  height: number;
  stroke: string;
}

// Decorative per-type detail drawn inside an object's own local frame
// (origin at its center, unrotated) — shared by the live canvas and the
// static export renderer so the two never visually drift apart.
export function ObjectGlyph({ entry, width, height, stroke }: GlyphProps) {
  if (width < 1 || height < 1) return null;

  switch (entry.id) {
    case 'orchard-trees':
      return <TreeGrid width={width} height={height} stroke={stroke} />;
    case 'berry-rows':
      return <RowLines width={width} height={height} stroke={stroke} rows={4} dashed />;
    case 'vineyard':
      return <RowLines width={width} height={height} stroke={stroke} rows={6} />;
    case 'raised-beds':
      return <BedGrid width={width} height={height} stroke={stroke} />;
    case 'potato-area':
    case 'grain-field':
    case 'vegetable-area':
      return <FurrowLines width={width} height={height} stroke={stroke} />;
    case 'greenhouse':
      return <GlassGrid width={width} height={height} stroke={stroke} />;
    case 'hydroponic-tower':
      return <TowerRack width={width} height={height} stroke={stroke} />;
    case 'solar-array':
      return <PanelGrid width={width} height={height} stroke={stroke} />;
    case 'patio':
      return <PaverGrid width={width} height={height} stroke={stroke} />;
    case 'compost':
      return <CompostMound width={width} height={height} stroke={stroke} />;
    case 'goat-paddock':
      return <PastureHatch width={width} height={height} stroke={stroke} />;
    case 'well':
      return <WellMark radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'water-tank':
      return <TankRings radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'pool':
      return <PoolRipples width={width} height={height} stroke={stroke} />;
    case 'gazebo':
      return <RadialRoof radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'house-l':
      return <LShapeRoofLines width={width} height={height} stroke={stroke} />;
    default:
      if (entry.shape === 'rect') {
        return <RoofLines width={width} height={height} stroke={stroke} withDoor={entry.id === 'house' || entry.id === 'garage'} />;
      }
      return null;
  }
}

// Notch cut from the front-right corner, shared with ObjectVisual's fill
// polygon so the glyph and the shape it sits on never disagree.
export function lShapeVertices(width: number, height: number): [number, number][] {
  const hw = width / 2;
  const hh = height / 2;
  const nx = Math.min(width * 0.42, width - 1.5);
  const ny = Math.min(height * 0.42, height - 1.5);
  return [
    [-hw, -hh],
    [hw, -hh],
    [hw, hh - ny],
    [hw - nx, hh - ny],
    [hw - nx, hh],
    [-hw, hh],
  ];
}

function RoofLines({ width, height, stroke, withDoor }: { width: number; height: number; stroke: string; withDoor: boolean }) {
  const hw = width / 2;
  const hh = height / 2;
  const corners = [
    { x: -hw, y: -hh },
    { x: hw, y: -hh },
    { x: hw, y: hh },
    { x: -hw, y: hh },
  ];
  return (
    <g opacity={0.6}>
      {corners.map((c, i) => (
        <line key={i} x1={c.x} y1={c.y} x2={0} y2={0} stroke={stroke} strokeWidth={0.06} />
      ))}
      {withDoor && width > 3 && (
        <line x1={-0.5} y1={hh} x2={0.5} y2={hh} stroke={stroke} strokeWidth={0.35} opacity={0.9} />
      )}
    </g>
  );
}

function TreeGrid({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const spacing = 2.6;
  const margin = 1.1;
  const cols = Math.max(1, Math.floor((width - margin * 2) / spacing) + 1);
  const rows = Math.max(1, Math.floor((height - margin * 2) / spacing) + 1);
  const cappedCols = Math.min(cols, 6);
  const cappedRows = Math.min(rows, 6);
  const trees: { x: number; y: number }[] = [];
  for (let r = 0; r < cappedRows; r++) {
    for (let c = 0; c < cappedCols; c++) {
      const x = -width / 2 + margin + (cappedCols === 1 ? width - margin * 2 : (c * (width - margin * 2)) / (cappedCols - 1));
      const y = -height / 2 + margin + (cappedRows === 1 ? height - margin * 2 : (r * (height - margin * 2)) / (cappedRows - 1));
      trees.push({ x, y });
    }
  }
  const canopyR = Math.min(0.85, spacing / 2.6);
  return (
    <g>
      {trees.map((t, i) => (
        <g key={i} transform={`translate(${t.x} ${t.y})`}>
          <circle r={canopyR} fill={stroke} fillOpacity={0.3} stroke={stroke} strokeWidth={0.07} />
          <circle r={canopyR * 0.22} fill={stroke} fillOpacity={0.55} />
        </g>
      ))}
    </g>
  );
}

function RowLines({ width, height, stroke, rows, dashed }: { width: number; height: number; stroke: string; rows: number; dashed?: boolean }) {
  const margin = 0.6;
  const usableH = height - margin * 2;
  if (usableH <= 0) return null;
  const lines = Array.from({ length: rows }, (_, i) => -height / 2 + margin + (rows === 1 ? usableH / 2 : (i * usableH) / (rows - 1)));
  return (
    <g opacity={0.65}>
      {lines.map((y, i) => (
        <line
          key={i}
          x1={-width / 2 + margin}
          y1={y}
          x2={width / 2 - margin}
          y2={y}
          stroke={stroke}
          strokeWidth={0.09}
          strokeDasharray={dashed ? '0.4,0.35' : undefined}
        />
      ))}
    </g>
  );
}

function FurrowLines({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const spacing = 1.1;
  const margin = 0.5;
  const usableH = height - margin * 2;
  if (usableH <= 0) return null;
  const count = Math.max(2, Math.floor(usableH / spacing));
  return (
    <g opacity={0.4}>
      {Array.from({ length: count + 1 }, (_, i) => -height / 2 + margin + (i * usableH) / count).map((y, i) => (
        <line key={i} x1={-width / 2 + margin} y1={y} x2={width / 2 - margin} y2={y} stroke={stroke} strokeWidth={0.05} />
      ))}
    </g>
  );
}

function BedGrid({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const cols = width >= height ? Math.min(4, Math.max(1, Math.round(width / 2.2))) : Math.min(3, Math.max(1, Math.round(width / 2.2)));
  const rows = Math.min(3, Math.max(1, Math.round(height / 2.2)));
  const gap = 0.35;
  const cellW = (width - gap * (cols + 1)) / cols;
  const cellH = (height - gap * (rows + 1)) / rows;
  if (cellW <= 0.3 || cellH <= 0.3) return null;
  const beds: { x: number; y: number }[] = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      beds.push({
        x: -width / 2 + gap + c * (cellW + gap),
        y: -height / 2 + gap + r * (cellH + gap),
      });
    }
  }
  return (
    <g opacity={0.75}>
      {beds.map((b, i) => (
        <rect key={i} x={b.x} y={b.y} width={cellW} height={cellH} fill="none" stroke={stroke} strokeWidth={0.07} />
      ))}
    </g>
  );
}

function GlassGrid({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const spacing = 1.3;
  const cols = Math.max(1, Math.round(width / spacing));
  const rows = Math.max(1, Math.round(height / spacing));
  const lines: React.ReactNode[] = [];
  for (let c = 1; c < cols; c++) {
    const x = -width / 2 + (c * width) / cols;
    lines.push(<line key={`v${c}`} x1={x} y1={-height / 2} x2={x} y2={height / 2} stroke={stroke} strokeWidth={0.05} />);
  }
  for (let r = 1; r < rows; r++) {
    const y = -height / 2 + (r * height) / rows;
    lines.push(<line key={`h${r}`} x1={-width / 2} y1={y} x2={width / 2} y2={y} stroke={stroke} strokeWidth={0.05} />);
  }
  return <g opacity={0.55}>{lines}</g>;
}

function TowerRack({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const cols = Math.max(1, Math.min(3, Math.round(width / 1.2)));
  const rows = Math.max(1, Math.min(3, Math.round(height / 1.2)));
  const r = Math.min(width / (cols * 2.4), height / (rows * 2.4), 0.4);
  const towers: { x: number; y: number }[] = [];
  for (let ri = 0; ri < rows; ri++) {
    for (let ci = 0; ci < cols; ci++) {
      towers.push({
        x: -width / 2 + (width * (ci + 0.5)) / cols,
        y: -height / 2 + (height * (ri + 0.5)) / rows,
      });
    }
  }
  return (
    <g>
      {towers.map((t, i) => (
        <circle key={i} cx={t.x} cy={t.y} r={r} fill={stroke} fillOpacity={0.25} stroke={stroke} strokeWidth={0.06} />
      ))}
    </g>
  );
}

function PanelGrid({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const cols = Math.max(2, Math.round(width / 1.6));
  const rows = Math.max(1, Math.round(height / 1.6));
  const gap = 0.15;
  const cellW = (width - gap * (cols + 1)) / cols;
  const cellH = (height - gap * (rows + 1)) / rows;
  if (cellW <= 0.2 || cellH <= 0.2) return null;
  const cells: { x: number; y: number }[] = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      cells.push({ x: -width / 2 + gap + c * (cellW + gap), y: -height / 2 + gap + r * (cellH + gap) });
    }
  }
  return (
    <g opacity={0.8}>
      {cells.map((cell, i) => (
        <rect key={i} x={cell.x} y={cell.y} width={cellW} height={cellH} fill="none" stroke={stroke} strokeWidth={0.06} />
      ))}
      <line x1={-width / 2 + 0.2} y1={height / 2 - 0.2} x2={width / 2 - 0.2} y2={-height / 2 + 0.2} stroke={stroke} strokeWidth={0.05} opacity={0.4} />
    </g>
  );
}

function PaverGrid({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const spacing = 1.4;
  const cols = Math.max(1, Math.round(width / spacing));
  const rows = Math.max(1, Math.round(height / spacing));
  const lines: React.ReactNode[] = [];
  for (let c = 1; c < cols; c++) {
    const x = -width / 2 + (c * width) / cols;
    lines.push(<line key={`v${c}`} x1={x} y1={-height / 2} x2={x} y2={height / 2} stroke={stroke} strokeWidth={0.05} />);
  }
  for (let r = 1; r < rows; r++) {
    const y = -height / 2 + (r * height) / rows;
    lines.push(<line key={`h${r}`} x1={-width / 2} y1={y} x2={width / 2} y2={y} stroke={stroke} strokeWidth={0.05} />);
  }
  return <g opacity={0.35}>{lines}</g>;
}

function CompostMound({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const s = Math.min(width, height) * 0.32;
  return (
    <g opacity={0.75}>
      <path d={`M ${-s} ${s} L 0 ${-s} L ${s} ${s} Z`} fill={stroke} fillOpacity={0.3} stroke={stroke} strokeWidth={0.07} />
      <circle cx={-s * 0.3} cy={s * 0.5} r={0.12} fill={stroke} />
      <circle cx={s * 0.35} cy={s * 0.6} r={0.12} fill={stroke} />
    </g>
  );
}

function PastureHatch({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const clipId = useId();
  const spacing = 1.6;
  const lines: React.ReactNode[] = [];
  const diag = Math.max(width, height) * 1.5;
  let i = 0;
  for (let offset = -diag; offset <= diag; offset += spacing) {
    lines.push(
      <line
        key={i++}
        x1={-width / 2}
        y1={-height / 2 + offset}
        x2={width / 2}
        y2={-height / 2 + offset + width}
        stroke={stroke}
        strokeWidth={0.05}
      />,
    );
  }
  return (
    <g opacity={0.3}>
      <clipPath id={clipId}>
        <rect x={-width / 2} y={-height / 2} width={width} height={height} />
      </clipPath>
      <g clipPath={`url(#${clipId})`}>{lines}</g>
    </g>
  );
}

function WellMark({ radius, stroke }: { radius: number; stroke: string }) {
  const r = radius * 0.4;
  return (
    <g opacity={0.8}>
      <circle r={r} fill="none" stroke={stroke} strokeWidth={0.08} />
      <line x1={-r * 0.6} y1={0} x2={r * 0.6} y2={0} stroke={stroke} strokeWidth={0.06} />
      <line x1={0} y1={-r * 0.6} x2={0} y2={r * 0.6} stroke={stroke} strokeWidth={0.06} />
    </g>
  );
}

function TankRings({ radius, stroke }: { radius: number; stroke: string }) {
  return (
    <g opacity={0.7}>
      <circle r={radius * 0.65} fill="none" stroke={stroke} strokeWidth={0.07} />
      <circle r={radius * 0.3} fill={stroke} fillOpacity={0.3} />
    </g>
  );
}

function PoolRipples({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const margin = Math.min(width, height) * 0.22;
  const rows = 3;
  const usableH = height - margin * 2;
  const amp = Math.min(0.3, usableH / 10);
  const waves: React.ReactNode[] = [];
  for (let r = 0; r < rows; r++) {
    const y = -height / 2 + margin + (r * usableH) / (rows - 1);
    const x0 = -width / 2 + margin * 0.6;
    const x1 = width / 2 - margin * 0.6;
    const mid = (x0 + x1) / 2;
    waves.push(
      <path
        key={r}
        d={`M ${x0} ${y} Q ${(x0 + mid) / 2} ${y - amp}, ${mid} ${y} T ${x1} ${y}`}
        fill="none"
        stroke={stroke}
        strokeWidth={0.07}
      />,
    );
  }
  return <g opacity={0.6}>{waves}</g>;
}

function RadialRoof({ radius, stroke }: { radius: number; stroke: string }) {
  const spokes = 8;
  const lines = Array.from({ length: spokes }, (_, i) => {
    const angle = (i / spokes) * Math.PI * 2;
    return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius };
  });
  return (
    <g opacity={0.6}>
      <circle r={radius * 0.15} fill={stroke} fillOpacity={0.5} />
      {lines.map((p, i) => (
        <line key={i} x1={0} y1={0} x2={p.x} y2={p.y} stroke={stroke} strokeWidth={0.05} />
      ))}
    </g>
  );
}

function LShapeRoofLines({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const pts = lShapeVertices(width, height);
  const cx = pts.reduce((sum, p) => sum + p[0], 0) / pts.length;
  const cy = pts.reduce((sum, p) => sum + p[1], 0) / pts.length;
  return (
    <g opacity={0.6}>
      {pts.map((p, i) => (
        <line key={i} x1={p[0]} y1={p[1]} x2={cx} y2={cy} stroke={stroke} strokeWidth={0.06} />
      ))}
      {width > 3 && <line x1={-0.5} y1={height / 2} x2={0.5} y2={height / 2} stroke={stroke} strokeWidth={0.35} opacity={0.9} />}
    </g>
  );
}
