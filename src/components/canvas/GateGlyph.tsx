import type { Plot, Point } from '../../domain/types';
import { pointInPolygon } from '../../engine/geometry';

// Closest point-to-segment distance, to find which boundary edge a gate
// point sits on (it's always exactly on one, but not tagged with which).
function nearestEdge(point: Point, polygon: Point[]): { a: Point; b: Point } {
  let best = { a: polygon[0], b: polygon[1 % polygon.length] };
  let bestDist = Infinity;
  for (let i = 0; i < polygon.length; i++) {
    const a = polygon[i];
    const b = polygon[(i + 1) % polygon.length];
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const lenSq = abx * abx + aby * aby || 1;
    const t = Math.max(0, Math.min(1, ((point.x - a.x) * abx + (point.y - a.y) * aby) / lenSq));
    const cx = a.x + abx * t;
    const cy = a.y + aby * t;
    const d = Math.hypot(point.x - cx, point.y - cy);
    if (d < bestDist) {
      bestDist = d;
      best = { a, b };
    }
  }
  return best;
}

// A small stylised double-gate — two posts with leaves swung open toward
// the plot interior — drawn at the point where the driveway/entrance path
// crosses the property line, so the boundary reads as an actual entrance
// rather than an unbroken fence line with paths that mysteriously start
// partway across it.
export function GateGlyph({ plot, point, bgColor }: { plot: Plot; point: Point; bgColor: string }) {
  const { a, b } = nearestEdge(point, plot.boundary);
  const len = Math.hypot(b.x - a.x, b.y - a.y) || 1;
  const dir = { x: (b.x - a.x) / len, y: (b.y - a.y) / len };
  let perp = { x: -dir.y, y: dir.x };
  if (!pointInPolygon({ x: point.x + perp.x * 0.5, y: point.y + perp.y * 0.5 }, plot.boundary)) {
    perp = { x: -perp.x, y: -perp.y };
  }

  const half = 1.6;
  const postA = { x: point.x - dir.x * half, y: point.y - dir.y * half };
  const postB = { x: point.x + dir.x * half, y: point.y + dir.y * half };
  const swing = 1.3;
  const leafA = { x: postA.x + perp.x * swing * 0.7 + dir.x * swing * 0.5, y: postA.y + perp.y * swing * 0.7 + dir.y * swing * 0.5 };
  const leafB = { x: postB.x + perp.x * swing * 0.7 - dir.x * swing * 0.5, y: postB.y + perp.y * swing * 0.7 - dir.y * swing * 0.5 };

  return (
    <g className="pointer-events-none">
      <line x1={postA.x} y1={postA.y} x2={postB.x} y2={postB.y} stroke={bgColor} strokeWidth={0.32} />
      <line x1={postA.x} y1={postA.y} x2={leafA.x} y2={leafA.y} stroke="#5c4433" strokeWidth={0.15} strokeLinecap="round" />
      <line x1={postB.x} y1={postB.y} x2={leafB.x} y2={leafB.y} stroke="#5c4433" strokeWidth={0.15} strokeLinecap="round" />
      <circle cx={postA.x} cy={postA.y} r={0.26} fill="#3f2e22" />
      <circle cx={postB.x} cy={postB.y} r={0.26} fill="#3f2e22" />
    </g>
  );
}
