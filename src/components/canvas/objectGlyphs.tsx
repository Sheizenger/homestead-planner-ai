import { useId } from 'react';
import type { ObjectLibraryEntry } from '../../domain/objectLibrary';
import type { Season } from '../../domain/types';

interface GlyphProps {
  entry: ObjectLibraryEntry;
  width: number;
  height: number;
  stroke: string;
  season?: Season;
}

// Decorative per-type detail drawn inside an object's own local frame
// (origin at its center, unrotated) — shared by the live canvas and the
// static export renderer so the two never visually drift apart. Every
// catalog entry gets its own representational icon (not a generic
// hatch/box) so the shape reads as "that specific thing" at a glance.
export function ObjectGlyph({ entry, width, height, stroke, season }: GlyphProps) {
  if (width < 1 || height < 1) return null;

  switch (entry.id) {
    case 'orchard-trees':
      return <TreeGrid width={width} height={height} stroke={stroke} season={season} />;
    case 'berry-rows':
      return <RowLines width={width} height={height} stroke={stroke} rows={4} dashed dormant={season === 'winter'} accent="berry" />;
    case 'vineyard':
      return <RowLines width={width} height={height} stroke={stroke} rows={6} dormant={season === 'winter'} accent="grape" />;
    case 'raised-beds':
      return <BedGrid width={width} height={height} stroke={stroke} />;
    case 'potato-area':
      return <FurrowLines width={width} height={height} stroke={stroke} fallow={season === 'winter'} variant="potato" />;
    case 'vegetable-area':
      return <FurrowLines width={width} height={height} stroke={stroke} fallow={season === 'winter'} variant="vegetable" />;
    case 'grain-field':
      return <FurrowLines width={width} height={height} stroke={stroke} fallow={season === 'winter'} />;
    case 'greenhouse':
      return <GlassGrid width={width} height={height} stroke={stroke} />;
    case 'hydroponic-tower':
      return <TowerRack width={width} height={height} stroke={stroke} />;
    case 'solar-array':
      return <PanelGrid width={width} height={height} stroke={stroke} />;
    case 'patio':
      return <PatioSet width={width} height={height} stroke={stroke} />;
    case 'compost':
      return <CompostMound width={width} height={height} stroke={stroke} />;
    case 'goat-paddock':
      return <PastureHatch width={width} height={height} stroke={stroke} />;
    case 'goat-shelter':
      return (
        <>
          <RoofLines width={width} height={height} stroke={stroke} withDoor={false} />
          <GoatMark width={width} height={height} stroke={stroke} />
        </>
      );
    case 'poultry-coop':
      return <CoopRun width={width} height={height} stroke={stroke} />;
    case 'well':
      return <WellMark radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'pump':
      return <PumpMark radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'water-tank':
    case 'rainwater-cistern':
      return <TankRings radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'septic':
      return <SepticLids width={width} height={height} stroke={stroke} />;
    case 'pool':
      return <PoolIcon width={width} height={height} stroke={stroke} />;
    case 'gazebo':
      return <RadialRoof radius={Math.min(width, height) / 2} stroke={stroke} />;
    case 'house-l':
      return <LShapeRoofLines width={width} height={height} stroke={stroke} />;
    case 'apiary':
      return <HiveRows width={width} height={height} stroke={stroke} />;
    case 'smokehouse':
      return <SmokeIcon height={height} stroke={stroke} />;
    case 'banya':
      return (
        <>
          <RoofLines width={width} height={height} stroke={stroke} withDoor={width > 3} />
          <SteamIcon width={width} height={height} stroke={stroke} />
        </>
      );
    case 'barn':
      return <BarnDoor width={width} height={height} stroke={stroke} />;
    case 'garage':
      return <GarageIcon width={width} height={height} stroke={stroke} />;
    case 'woodshed':
      return (
        <>
          <RoofLines width={width} height={height} stroke={stroke} withDoor={false} />
          <LogPile width={width} height={height} stroke={stroke} />
        </>
      );
    case 'workshop':
      return (
        <>
          <RoofLines width={width} height={height} stroke={stroke} withDoor={width > 3} />
          <GearIcon width={width} height={height} stroke={stroke} />
        </>
      );
    case 'cellar':
      return <CellarMound width={width} height={height} stroke={stroke} />;
    case 'battery-room':
      return <BatteryIcon width={width} height={height} stroke={stroke} />;
    case 'inverter-room':
      return <BoltIcon width={width} height={height} stroke={stroke} />;
    case 'generator':
      return <GeneratorIcon width={width} height={height} stroke={stroke} />;
    case 'dock':
      return <DockPlanks width={width} height={height} stroke={stroke} />;
    case 'micro-hydro':
      return <TurbineIcon width={width} height={height} stroke={stroke} />;
    default:
      if (entry.shape === 'rect') {
        return <RoofLines width={width} height={height} stroke={stroke} withDoor={['house', 'shed'].includes(entry.id)} />;
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

// Classic architectural roof-plan symbol: a ridge along the longer axis with
// four hip lines sloping down to the corners, rather than a plain corner-to-
// center X — reads as an actual pitched roof instead of an abstract star.
function RoofLines({ width, height, stroke, withDoor }: { width: number; height: number; stroke: string; withDoor: boolean }) {
  const hw = width / 2;
  const hh = height / 2;
  const horizontal = width >= height;
  const ridgeHalf = Math.max(0, (horizontal ? hw : hh) - Math.min(hw, hh) * 0.9);
  const ridgeA = horizontal ? { x: -ridgeHalf, y: 0 } : { x: 0, y: -ridgeHalf };
  const ridgeB = horizontal ? { x: ridgeHalf, y: 0 } : { x: 0, y: ridgeHalf };
  const corners = [
    { x: -hw, y: -hh },
    { x: hw, y: -hh },
    { x: hw, y: hh },
    { x: -hw, y: hh },
  ];
  return (
    <g opacity={0.65}>
      <line x1={ridgeA.x} y1={ridgeA.y} x2={ridgeB.x} y2={ridgeB.y} stroke={stroke} strokeWidth={0.09} />
      {corners.map((c, i) => {
        const anchor = (horizontal ? c.x < 0 : c.y < 0) ? ridgeA : ridgeB;
        return <line key={i} x1={c.x} y1={c.y} x2={anchor.x} y2={anchor.y} stroke={stroke} strokeWidth={0.06} />;
      })}
      {withDoor && width > 3 && (
        <line x1={-0.5} y1={hh} x2={0.5} y2={hh} stroke={stroke} strokeWidth={0.35} opacity={0.9} />
      )}
    </g>
  );
}

function TreeGrid({ width, height, stroke, season }: { width: number; height: number; stroke: string; season?: Season }) {
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
  // Winter: bare canopy (outline only, no fill, no fruit dot). Spring:
  // blossom tint. Autumn: fruit/foliage tint. Summer/undefined: default green.
  const canopyFill = season === 'spring' ? '#e9b8c9' : season === 'autumn' ? '#c9772e' : stroke;
  const showCanopyFill = season !== 'winter';
  const showFruitDot = season === 'autumn' || season === undefined || season === 'summer';
  return (
    <g>
      {trees.map((t, i) => (
        <TreeIcon
          key={i}
          x={t.x}
          y={t.y}
          r={canopyR}
          stroke={stroke}
          canopyFill={canopyFill}
          showCanopyFill={showCanopyFill}
          showFruitDot={showFruitDot}
          winter={season === 'winter'}
        />
      ))}
    </g>
  );
}

// A trunk plus a 3-lobe overlapping-circle crown reads as an actual tree
// (canopy + trunk) at plan-view scale, rather than a single flat dot.
function TreeIcon({
  x,
  y,
  r,
  stroke,
  canopyFill,
  showCanopyFill,
  showFruitDot,
  winter,
}: {
  x: number;
  y: number;
  r: number;
  stroke: string;
  canopyFill: string;
  showCanopyFill: boolean;
  showFruitDot: boolean;
  winter: boolean;
}) {
  const lobes = [
    { dx: 0, dy: -r * 0.32, lr: r * 0.72 },
    { dx: -r * 0.42, dy: r * 0.08, lr: r * 0.56 },
    { dx: r * 0.42, dy: r * 0.08, lr: r * 0.56 },
  ];
  return (
    <g transform={`translate(${x} ${y})`}>
      <line x1={0} y1={r * 0.3} x2={0} y2={r * 0.95} stroke={stroke} strokeWidth={0.06} opacity={0.75} />
      {lobes.map((l, i) => (
        <circle
          key={i}
          cx={l.dx}
          cy={l.dy}
          r={l.lr}
          fill={showCanopyFill ? canopyFill : 'none'}
          fillOpacity={0.32}
          stroke={stroke}
          strokeWidth={0.06}
          strokeDasharray={winter ? '0.14,0.11' : undefined}
        />
      ))}
      {showFruitDot && <circle cy={-r * 0.25} r={r * 0.2} fill={canopyFill} fillOpacity={0.55} />}
    </g>
  );
}

// Trellis rows for vineyard/berries. An accent mark repeated along the rows
// — a tiny grape cluster or a tiny berry bush — turns "some parallel lines"
// into "that's clearly a vineyard/berry patch" without cluttering the plan.
function RowLines({
  width,
  height,
  stroke,
  rows,
  dashed,
  dormant,
  accent,
}: {
  width: number;
  height: number;
  stroke: string;
  rows: number;
  dashed?: boolean;
  dormant?: boolean;
  accent?: 'grape' | 'berry';
}) {
  const margin = 0.6;
  const usableH = height - margin * 2;
  if (usableH <= 0) return null;
  const lineYs = Array.from({ length: rows }, (_, i) => -height / 2 + margin + (rows === 1 ? usableH / 2 : (i * usableH) / (rows - 1)));
  const usableW = width - margin * 2;
  const accentSpacing = 1.5;
  const accentCols = accent && usableW > 0 ? Math.max(1, Math.floor(usableW / accentSpacing)) : 0;
  return (
    <g opacity={dormant ? 0.35 : 0.65}>
      {lineYs.map((y, i) => (
        <line
          key={i}
          x1={-width / 2 + margin}
          y1={y}
          x2={width / 2 - margin}
          y2={y}
          stroke={stroke}
          strokeWidth={dormant ? 0.05 : 0.09}
          strokeDasharray={dashed ? '0.4,0.35' : undefined}
        />
      ))}
      {accent &&
        !dormant &&
        lineYs
          .filter((_, ri) => accent !== 'grape' || ri % 2 === 1) // grape clusters on alternating rows only, keeps it legible
          .map((y, ri) =>
            Array.from({ length: accentCols }, (_, ci) => {
              const x = -width / 2 + margin + ((ci + 0.5) * usableW) / accentCols;
              return accent === 'grape' ? (
                <g key={`${ri}-${ci}`} transform={`translate(${x} ${y})`}>
                  <circle cx={-0.09} cy={0.09} r={0.08} fill={stroke} fillOpacity={0.5} />
                  <circle cx={0.09} cy={0.09} r={0.08} fill={stroke} fillOpacity={0.5} />
                  <circle cx={0} cy={-0.05} r={0.08} fill={stroke} fillOpacity={0.5} />
                </g>
              ) : (
                <ellipse key={`${ri}-${ci}`} cx={x} cy={y} rx={0.18} ry={0.12} fill={stroke} fillOpacity={0.3} stroke={stroke} strokeWidth={0.04} />
              );
            }),
          )}
    </g>
  );
}

// Potato hills read as small filled mounds; vegetable rows read as evenly
// spaced open circles (individual plants); a grain field stays pure texture
// lines, matching the real cartographic convention for a dense field crop.
function FurrowLines({
  width,
  height,
  stroke,
  fallow,
  variant,
}: {
  width: number;
  height: number;
  stroke: string;
  fallow?: boolean;
  variant?: 'potato' | 'vegetable';
}) {
  if (fallow) return null; // bare/tilled soil over winter — no crop rows to show
  const spacing = 1.1;
  const margin = 0.5;
  const usableH = height - margin * 2;
  if (usableH <= 0) return null;
  const count = Math.max(2, Math.floor(usableH / spacing));
  const rowYs = Array.from({ length: count + 1 }, (_, i) => -height / 2 + margin + (i * usableH) / count);
  const usableW = width - margin * 2;
  const dotCols = variant && usableW > 0 ? Math.max(1, Math.floor(usableW / 1.0)) : 0;
  return (
    <g opacity={0.4}>
      {rowYs.map((y, i) => (
        <line key={i} x1={-width / 2 + margin} y1={y} x2={width / 2 - margin} y2={y} stroke={stroke} strokeWidth={0.05} />
      ))}
      {variant &&
        rowYs.slice(0, -1).map((y, ri) => {
          const yMid = y + (rowYs[ri + 1] - y) / 2;
          return Array.from({ length: dotCols }, (_, ci) => {
            const x = -width / 2 + margin + ((ci + 0.5) * usableW) / dotCols;
            return variant === 'potato' ? (
              <circle key={`${ri}-${ci}`} cx={x} cy={yMid} r={0.1} fill={stroke} fillOpacity={0.4} />
            ) : (
              <circle key={`${ri}-${ci}`} cx={x} cy={yMid} r={0.13} fill="none" stroke={stroke} strokeWidth={0.04} opacity={0.6} />
            );
          });
        })}
    </g>
  );
}

// Each bed gets a small sprout tick (a planted seedling) so the grid reads
// as a kitchen garden, not just an arbitrary set of rectangles.
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
      {beds.map((b, i) => {
        const cx = b.x + cellW / 2;
        const cy = b.y + cellH / 2;
        return (
          <g key={i}>
            <rect x={b.x} y={b.y} width={cellW} height={cellH} fill="none" stroke={stroke} strokeWidth={0.07} />
            {cellW > 0.6 && cellH > 0.6 && (
              <path d={`M ${cx} ${cy + 0.16} l -0.12 -0.24 M ${cx} ${cy + 0.16} l 0.12 -0.24`} stroke={stroke} strokeWidth={0.05} opacity={0.65} />
            )}
          </g>
        );
      })}
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
  return (
    <g opacity={0.55}>
      <path d={`M ${-width / 2} ${-height / 2 + 0.6} Q 0 ${-height / 2 - 0.3} ${width / 2} ${-height / 2 + 0.6}`} fill="none" stroke={stroke} strokeWidth={0.08} opacity={0.7} />
      {lines}
    </g>
  );
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
        <g key={i} transform={`translate(${t.x} ${t.y})`}>
          <circle r={r} fill={stroke} fillOpacity={0.2} stroke={stroke} strokeWidth={0.06} />
          <circle r={r * 0.55} fill="none" stroke={stroke} strokeWidth={0.05} />
          <circle r={r * 0.15} fill={stroke} />
        </g>
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
        <rect key={i} x={cell.x} y={cell.y} width={cellW} height={cellH} fill={stroke} fillOpacity={0.12} stroke={stroke} strokeWidth={0.06} />
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

// Paving texture plus a patio umbrella (canopy seen from above, with a
// scalloped dashed edge and a pole dot) surrounded by four small chairs —
// unmistakably "outdoor seating", not just a paved rectangle.
function PatioSet({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const r = Math.min(width, height) * 0.24;
  const chairR = r * 0.4;
  const chairDist = r * 1.55;
  const fits = width > 2.6 && height > 2.6;
  const chairs = fits
    ? [45, 135, 225, 315].map((deg) => {
        const rad = (deg * Math.PI) / 180;
        return { x: Math.cos(rad) * chairDist, y: Math.sin(rad) * chairDist };
      })
    : [];
  return (
    <g>
      <PaverGrid width={width} height={height} stroke={stroke} />
      <g opacity={0.85}>
        <circle r={r} fill={stroke} fillOpacity={0.22} stroke={stroke} strokeWidth={0.07} strokeDasharray="0.2,0.16" />
        <circle r={r * 0.09} fill={stroke} />
        {chairs.map((c, i) => (
          <rect key={i} x={c.x - chairR / 2} y={c.y - chairR / 2} width={chairR} height={chairR} rx={0.05} fill="none" stroke={stroke} strokeWidth={0.06} />
        ))}
      </g>
    </g>
  );
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

// A stylized goat-head mark (triangular face + two curved horns) so the
// shelter reads as "houses goats", not a generic shed.
function GoatMark({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const s = Math.min(width, height) * 0.22;
  if (s < 0.3) return null;
  return (
    <g opacity={0.8}>
      <path d={`M 0 ${-s * 0.6} L ${-s * 0.5} ${s * 0.5} L ${s * 0.5} ${s * 0.5} Z`} fill="none" stroke={stroke} strokeWidth={0.07} />
      <path d={`M ${-s * 0.15} ${-s * 0.6} q -0.18 -0.32 -0.06 -0.55`} fill="none" stroke={stroke} strokeWidth={0.06} />
      <path d={`M ${s * 0.15} ${-s * 0.6} q 0.18 -0.32 0.06 -0.55`} fill="none" stroke={stroke} strokeWidth={0.06} />
    </g>
  );
}

// A small coop roof on one end, wire-run fencing (light vertical dashes) on
// the rest of the footprint — hen house plus its run, not a plain rectangle.
function CoopRun({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const coopW = Math.min(width * 0.4, height * 1.1);
  const runStart = -width / 2 + coopW;
  const runLines = Math.max(2, Math.floor((width / 2 - runStart) / 0.7));
  return (
    <g opacity={0.7}>
      <g transform={`translate(${-width / 2 + coopW / 2} 0)`}>
        <RoofLines width={coopW} height={Math.min(height * 0.85, coopW * 1.2)} stroke={stroke} withDoor={false} />
      </g>
      {Array.from({ length: runLines }, (_, i) => {
        const x = runStart + 0.5 + (i * (width / 2 - runStart - 0.6)) / Math.max(1, runLines - 1);
        return <line key={i} x1={x} y1={-height / 2 + 0.25} x2={x} y2={height / 2 - 0.25} stroke={stroke} strokeWidth={0.04} strokeDasharray="0.1,0.16" opacity={0.55} />;
      })}
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

// A hand-pump silhouette (base, spout, curved handle) — distinct from the
// plain crosshair well mark, since a pump house isn't the water source itself.
function PumpMark({ radius, stroke }: { radius: number; stroke: string }) {
  const r = radius * 0.55;
  return (
    <g opacity={0.85}>
      <circle cy={r * 0.35} r={r * 0.45} fill="none" stroke={stroke} strokeWidth={0.08} />
      <line x1={0} y1={-r * 0.15} x2={0} y2={-r * 0.95} stroke={stroke} strokeWidth={0.08} />
      <path d={`M 0 ${-r * 0.8} q ${r * 0.65} ${-r * 0.15} ${r * 0.6} ${r * 0.35}`} fill="none" stroke={stroke} strokeWidth={0.07} />
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

// Underground infrastructure, not a building — a dashed buried-tank outline
// plus two round manhole access lids, no roof at all.
function SepticLids({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const r = Math.min(width, height) * 0.15;
  const offset = width * 0.22;
  return (
    <g opacity={0.75}>
      <rect x={-width / 2 + 0.3} y={-height / 2 + 0.3} width={Math.max(0, width - 0.6)} height={Math.max(0, height - 0.6)} fill="none" stroke={stroke} strokeWidth={0.06} strokeDasharray="0.3,0.24" />
      <circle cx={-offset} r={r} fill="none" stroke={stroke} strokeWidth={0.07} />
      <circle cx={offset} r={r} fill="none" stroke={stroke} strokeWidth={0.07} />
    </g>
  );
}

// Ripples plus a coping border and a corner ladder — the ripples alone read
// as "wavy lines"; the ladder is what makes it unmistakably a swimming pool.
function PoolIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const margin = Math.min(width, height) * 0.16;
  return (
    <g>
      <ellipse rx={width / 2 - margin * 0.35} ry={height / 2 - margin * 0.35} fill="none" stroke={stroke} strokeWidth={0.07} strokeDasharray="0.28,0.22" opacity={0.55} />
      <PoolRipples width={width - margin} height={height - margin} stroke={stroke} />
      {width > 3 && (
        <g transform={`translate(${width / 2 - margin * 0.9} 0)`} opacity={0.85}>
          <line x1={-0.16} y1={-0.45} x2={-0.16} y2={0.45} stroke={stroke} strokeWidth={0.06} />
          <line x1={0.16} y1={-0.45} x2={0.16} y2={0.45} stroke={stroke} strokeWidth={0.06} />
          <line x1={-0.16} y1={-0.18} x2={0.16} y2={-0.18} stroke={stroke} strokeWidth={0.06} />
          <line x1={-0.16} y1={0.18} x2={0.16} y2={0.18} stroke={stroke} strokeWidth={0.06} />
        </g>
      )}
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

function HiveRows({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const spacing = 1.3;
  const margin = 0.5;
  const cols = Math.max(1, Math.min(4, Math.floor((width - margin * 2) / spacing) + 1));
  const rows = Math.max(1, Math.min(2, Math.floor((height - margin * 2) / spacing) + 1));
  const boxW = Math.min(0.8, spacing * 0.7);
  const boxH = Math.min(0.6, spacing * 0.55);
  const hives: { x: number; y: number }[] = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      hives.push({
        x: -width / 2 + margin + (cols === 1 ? width - margin * 2 : (c * (width - margin * 2)) / (cols - 1)),
        y: -height / 2 + margin + (rows === 1 ? height - margin * 2 : (r * (height - margin * 2)) / (rows - 1)),
      });
    }
  }
  return (
    <g opacity={0.75}>
      {hives.map((h, i) => (
        <rect key={i} x={h.x - boxW / 2} y={h.y - boxH / 2} width={boxW} height={boxH} fill={stroke} fillOpacity={0.3} stroke={stroke} strokeWidth={0.06} />
      ))}
    </g>
  );
}

function SmokeIcon({ height, stroke }: { height: number; stroke: string }) {
  const cx = 0;
  const top = -height / 2;
  return (
    <g opacity={0.7}>
      <path
        d={`M ${cx} ${top + 0.2} C ${cx + 0.4} ${top - 0.3}, ${cx - 0.4} ${top - 0.7}, ${cx} ${top - 1.1}`}
        fill="none"
        stroke={stroke}
        strokeWidth={0.08}
      />
      <rect x={cx - 0.2} y={top + 0.1} width={0.4} height={0.3} fill={stroke} />
    </g>
  );
}

// Soft rising steam wisps above the roofline — distinct from the
// smokehouse's single chimney, reads as heat/steam rather than a fire flue.
function SteamIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const hh = height / 2;
  const wisps = [-0.4, 0, 0.4].filter((dx) => Math.abs(dx) < width / 2 - 0.3);
  return (
    <g opacity={0.6}>
      {wisps.map((dx, i) => (
        <path
          key={i}
          d={`M ${dx} ${-hh * 0.15} C ${dx + 0.22} ${-hh * 0.5}, ${dx - 0.22} ${-hh * 0.75}, ${dx} ${-hh * 1.05}`}
          fill="none"
          stroke={stroke}
          strokeWidth={0.06}
        />
      ))}
    </g>
  );
}

// Wide double barn doors on the gable end — the scale difference from a
// house's small door mark is what reads as "barn" rather than "house".
function BarnDoor({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const hh = height / 2;
  const doorW = Math.min(width * 0.55, 3.4);
  const doorH = Math.min(height * 0.4, 1.6);
  return (
    <g opacity={0.75}>
      <RoofLines width={width} height={height} stroke={stroke} withDoor={false} />
      <rect x={-doorW / 2} y={hh - doorH} width={doorW} height={doorH} fill="none" stroke={stroke} strokeWidth={0.08} />
      <line x1={0} y1={hh - doorH} x2={0} y2={hh} stroke={stroke} strokeWidth={0.06} />
    </g>
  );
}

// A wide segmented "up-and-over" door on the road-facing edge plus a simple
// top-down parked-car silhouette — makes it unambiguous that this box is a
// vehicle garage (and where the driveway is meant to lead), not just another
// tool shed.
function GarageIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const hh = height / 2;
  const doorW = Math.min(width * 0.72, 4.2);
  const doorH = Math.min(height * 0.3, 1.2);
  const panels = 4;
  const panelW = doorW / panels;
  const carW = Math.min(doorW * 0.75, width * 0.55);
  const carH = Math.min(height * 0.5, height - doorH - 0.6);
  return (
    <g opacity={0.75}>
      <RoofLines width={width} height={height} stroke={stroke} withDoor={false} />
      <rect x={-doorW / 2} y={hh - doorH} width={doorW} height={doorH} fill="none" stroke={stroke} strokeWidth={0.08} />
      {Array.from({ length: panels - 1 }, (_, i) => {
        const x = -doorW / 2 + panelW * (i + 1);
        return <line key={i} x1={x} y1={hh - doorH} x2={x} y2={hh} stroke={stroke} strokeWidth={0.05} />;
      })}
      {carW > 1.3 && carH > 1.8 && (
        <g transform={`translate(0 ${hh - doorH - carH / 2 - 0.3})`} opacity={0.85}>
          <rect x={-carW / 2} y={-carH / 2} width={carW} height={carH} rx={carW * 0.28} fill="none" stroke={stroke} strokeWidth={0.09} />
          {[-1, 1].flatMap((sx) =>
            [-1, 1].map((sy) => (
              <circle
                key={`${sx}-${sy}`}
                cx={sx * carW * 0.32}
                cy={sy * carH * 0.3}
                r={Math.min(0.22, carW * 0.12)}
                fill="none"
                stroke={stroke}
                strokeWidth={0.07}
              />
            )),
          )}
        </g>
      )}
    </g>
  );
}

// Stacked log ends (circles in a settling pyramid) — a woodpile, not a
// generic storage shed.
function LogPile({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const r = Math.min(0.26, height / 7, width / 10);
  if (r < 0.08) return null;
  const baseCount = Math.max(3, Math.floor((width - 0.6) / (r * 1.7)));
  const rows = Math.min(3, baseCount - 1);
  const baseY = height / 2 - r - 0.2;
  const logs: { x: number; y: number }[] = [];
  for (let row = 0; row < rows; row++) {
    const n = baseCount - row;
    const rowWidth = (n - 1) * r * 1.7;
    for (let i = 0; i < n; i++) {
      logs.push({ x: -rowWidth / 2 + i * r * 1.7, y: baseY - row * r * 1.6 });
    }
  }
  return (
    <g opacity={0.75}>
      {logs.map((l, i) => (
        <circle key={i} cx={l.x} cy={l.y} r={r} fill="none" stroke={stroke} strokeWidth={0.06} />
      ))}
    </g>
  );
}

// A gear/cog outline — the universal "tools & mechanical work" mark.
function GearIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const r = Math.min(width, height) * 0.2;
  if (r < 0.3) return null;
  const teeth = 8;
  const outerR = r * 1.35;
  const points: string[] = [];
  for (let i = 0; i < teeth * 2; i++) {
    const angle = (i / (teeth * 2)) * Math.PI * 2;
    const rad = i % 2 === 0 ? outerR : r;
    points.push(`${Math.cos(angle) * rad},${Math.sin(angle) * rad}`);
  }
  return (
    <g opacity={0.75}>
      <polygon points={points.join(' ')} fill="none" stroke={stroke} strokeWidth={0.07} />
      <circle r={r * 0.35} fill="none" stroke={stroke} strokeWidth={0.06} />
    </g>
  );
}

// An earth-sheltered mound contour plus a small arched doorway, in place of
// a flat roof outline — reads as "dug into the ground", not an ordinary shed.
function CellarMound({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const hh = height / 2;
  const hw = width / 2;
  return (
    <g opacity={0.7}>
      <path d={`M ${-hw + 0.4} ${-hh + 0.5} Q 0 ${-hh - 0.4} ${hw - 0.4} ${-hh + 0.5}`} fill="none" stroke={stroke} strokeWidth={0.07} strokeDasharray="0.24,0.2" />
      <path d={`M -0.4 ${hh} L -0.4 ${hh - 0.6} A 0.4 0.4 0 0 1 0.4 ${hh - 0.6} L 0.4 ${hh}`} fill="none" stroke={stroke} strokeWidth={0.07} />
    </g>
  );
}

// Battery pictogram: body + terminal nub + two charge bars.
function BatteryIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const w = Math.min(width, height) * 0.65;
  const h = w * 0.55;
  const nub = w * 0.12;
  return (
    <g opacity={0.8}>
      <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={0.06} fill="none" stroke={stroke} strokeWidth={0.08} />
      <rect x={w / 2} y={-nub / 2} width={nub} height={nub} fill={stroke} />
      <line x1={-w * 0.18} y1={-h * 0.3} x2={-w * 0.18} y2={h * 0.3} stroke={stroke} strokeWidth={0.09} />
      <line x1={w * 0.05} y1={-h * 0.22} x2={w * 0.05} y2={h * 0.22} stroke={stroke} strokeWidth={0.09} />
    </g>
  );
}

// A lightning-bolt silhouette — the universal power-conversion mark.
function BoltIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const s = Math.min(width, height) * 0.42;
  return (
    <path
      d={`M ${s * 0.15} ${-s} L ${-s * 0.5} ${s * 0.15} L ${-s * 0.05} ${s * 0.15} L ${-s * 0.2} ${s} L ${s * 0.55} ${-s * 0.05} L ${s * 0.1} ${-s * 0.05} Z`}
      fill={stroke}
      fillOpacity={0.55}
      stroke={stroke}
      strokeWidth={0.05}
      opacity={0.85}
    />
  );
}

// A boxy engine block with a flywheel circle and a short curved exhaust puff.
function GeneratorIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const w = Math.min(width, height) * 0.6;
  const h = w * 0.7;
  return (
    <g opacity={0.8}>
      <rect x={-w / 2} y={-h / 2} width={w} height={h} rx={0.06} fill="none" stroke={stroke} strokeWidth={0.08} />
      <circle cx={-w * 0.15} r={h * 0.28} fill="none" stroke={stroke} strokeWidth={0.06} />
      <path d={`M ${w / 2} ${-h * 0.15} q ${h * 0.35} ${-h * 0.15} ${h * 0.3} ${-h * 0.5}`} fill="none" stroke={stroke} strokeWidth={0.05} opacity={0.7} />
    </g>
  );
}

// Cross-plank ties along the dock's long axis (like a real pier deck) plus a
// small moored boat at the water end — reads as "walk out onto this", not a
// plain rectangle.
function DockPlanks({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const alongY = height >= width;
  const spacing = 0.9;
  const lines: React.ReactNode[] = [];
  if (alongY) {
    const count = Math.max(2, Math.floor(height / spacing));
    for (let i = 0; i <= count; i++) {
      const y = -height / 2 + (i * height) / count;
      lines.push(<line key={i} x1={-width / 2 + 0.1} y1={y} x2={width / 2 - 0.1} y2={y} stroke={stroke} strokeWidth={0.05} opacity={0.55} />);
    }
  } else {
    const count = Math.max(2, Math.floor(width / spacing));
    for (let i = 0; i <= count; i++) {
      const x = -width / 2 + (i * width) / count;
      lines.push(<line key={i} x1={x} y1={-height / 2 + 0.1} x2={x} y2={height / 2 - 0.1} stroke={stroke} strokeWidth={0.05} opacity={0.55} />);
    }
  }
  const boatX = alongY ? 0 : width / 2 - 0.7;
  const boatY = alongY ? height / 2 - 0.7 : 0;
  const boatRx = alongY ? 0.45 : 0.32;
  const boatRy = alongY ? 0.32 : 0.45;
  return (
    <g opacity={0.8}>
      {lines}
      <ellipse cx={boatX} cy={boatY} rx={boatRx} ry={boatRy} fill={stroke} fillOpacity={0.3} stroke={stroke} strokeWidth={0.06} />
    </g>
  );
}

// Three curved blades around a hub, with small flow chevrons on either side
// indicating moving water — a water turbine, not a generic energy box.
function TurbineIcon({ width, height, stroke }: { width: number; height: number; stroke: string }) {
  const r = Math.min(width, height) * 0.3;
  const blades = [0, 120, 240].map((deg) => (deg * Math.PI) / 180);
  return (
    <g opacity={0.8}>
      <circle r={r} fill="none" stroke={stroke} strokeWidth={0.07} />
      {blades.map((rad, i) => {
        const bx = Math.cos(rad) * r * 0.85;
        const by = Math.sin(rad) * r * 0.85;
        const cx = Math.cos(rad + 0.9) * r * 0.55;
        const cy = Math.sin(rad + 0.9) * r * 0.55;
        return <path key={i} d={`M 0 0 Q ${cx} ${cy}, ${bx} ${by}`} fill="none" stroke={stroke} strokeWidth={0.08} />;
      })}
      <circle r={r * 0.15} fill={stroke} />
      <path d={`M ${-r * 1.7} 0 l 0.22 -0.18 M ${-r * 1.7} 0 l 0.22 0.18`} stroke={stroke} strokeWidth={0.06} opacity={0.6} fill="none" />
      <path d={`M ${r * 1.7} 0 l 0.22 -0.18 M ${r * 1.7} 0 l 0.22 0.18`} stroke={stroke} strokeWidth={0.06} opacity={0.6} fill="none" />
    </g>
  );
}
