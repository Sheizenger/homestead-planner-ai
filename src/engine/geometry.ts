import type { Point, Transform } from '../domain/types';

export interface Bounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export function polygonBounds(points: Point[]): Bounds {
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  return { minX: Math.min(...xs), minY: Math.min(...ys), maxX: Math.max(...xs), maxY: Math.max(...ys) };
}

// Ray-casting point-in-polygon test.
export function pointInPolygon(point: Point, polygon: Point[]): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const xi = polygon[i].x, yi = polygon[i].y;
    const xj = polygon[j].x, yj = polygon[j].y;
    const intersect =
      yi > point.y !== yj > point.y &&
      point.x < ((xj - xi) * (point.y - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

export function polygonArea(points: Point[]): number {
  let sum = 0;
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return Math.abs(sum) / 2;
}

export function rectCorners(t: Transform): Point[] {
  const hw = t.width / 2;
  const hh = t.height / 2;
  const rad = (t.rotationDeg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  const local: Point[] = [
    { x: -hw, y: -hh },
    { x: hw, y: -hh },
    { x: hw, y: hh },
    { x: -hw, y: hh },
  ];
  return local.map((p) => ({
    x: t.x + p.x * cos - p.y * sin,
    y: t.y + p.x * sin + p.y * cos,
  }));
}

// All generator-placed objects use rotationDeg 0 or 90 (axis-aligned), so
// AABB overlap is exact, not an approximation.
export function transformAabb(t: Transform): Bounds {
  const rotated = t.rotationDeg % 180 !== 0;
  const w = rotated ? t.height : t.width;
  const h = rotated ? t.width : t.height;
  return { minX: t.x - w / 2, minY: t.y - h / 2, maxX: t.x + w / 2, maxY: t.y + h / 2 };
}

export function aabbOverlap(a: Bounds, b: Bounds, margin = 0): boolean {
  return (
    a.minX - margin < b.maxX &&
    a.maxX + margin > b.minX &&
    a.minY - margin < b.maxY &&
    a.maxY + margin > b.minY
  );
}

// True if segments a1-a2 and b1-b2 cross at an interior point of both. Shared
// endpoints or collinear/touching edges are deliberately NOT reported as an
// intersection (all cross-product signs land at/near zero), since candidates
// routinely sit flush against — or share a corner with — the polygon boundary.
export function segmentsIntersect(a1: Point, a2: Point, b1: Point, b2: Point): boolean {
  const cross = (o: Point, p: Point, q: Point) => (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x);
  const d1 = cross(b1, b2, a1);
  const d2 = cross(b1, b2, a2);
  const d3 = cross(a1, a2, b1);
  const d4 = cross(a1, a2, b2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

// Corner-in-polygon alone is unsound for a concave boundary (e.g. an L-shaped
// plot): a rectangle can have all 4 corners inside the L while still
// bridging straight across the missing notch. So also reject any candidate
// whose own edges cross a polygon edge, which catches that bridging case.
export function rectFullyInsidePolygon(t: Transform, polygon: Point[]): boolean {
  const corners = rectCorners(t);
  if (!corners.every((c) => pointInPolygon(c, polygon))) return false;
  for (let i = 0; i < corners.length; i++) {
    const a = corners[i];
    const b = corners[(i + 1) % corners.length];
    for (let j = 0; j < polygon.length; j++) {
      if (segmentsIntersect(a, b, polygon[j], polygon[(j + 1) % polygon.length])) return false;
    }
  }
  return true;
}

// Sutherland-Hodgman polygon clip: intersects `subject` (any polygon, convex
// or concave) against an axis-aligned rectangle `clip`. Used to keep a
// bounds-derived shape (e.g. the waterfront strip) from rendering outside
// the plot's real boundary once that boundary isn't a plain rectangle.
export function clipPolygonToRect(subject: Point[], clip: Bounds): Point[] {
  const edges: [Point, Point][] = [
    [{ x: clip.minX, y: clip.minY }, { x: clip.maxX, y: clip.minY }],
    [{ x: clip.maxX, y: clip.minY }, { x: clip.maxX, y: clip.maxY }],
    [{ x: clip.maxX, y: clip.maxY }, { x: clip.minX, y: clip.maxY }],
    [{ x: clip.minX, y: clip.maxY }, { x: clip.minX, y: clip.minY }],
  ];
  let output = subject;
  for (const [e1, e2] of edges) {
    if (output.length === 0) break;
    const input = output;
    output = [];
    const inside = (p: Point) => (e2.x - e1.x) * (p.y - e1.y) - (e2.y - e1.y) * (p.x - e1.x) >= 0;
    const intersect = (p: Point, q: Point): Point => {
      const a1 = e2.x - e1.x, a2 = e2.y - e1.y;
      const b1 = q.x - p.x, b2 = q.y - p.y;
      const denom = a1 * b2 - a2 * b1;
      if (Math.abs(denom) < 1e-9) return p;
      const t = ((p.x - e1.x) * b2 - (p.y - e1.y) * b1) / denom;
      return { x: e1.x + a1 * t, y: e1.y + a2 * t };
    };
    for (let i = 0; i < input.length; i++) {
      const curr = input[i];
      const prev = input[(i - 1 + input.length) % input.length];
      const currIn = inside(curr);
      const prevIn = inside(prev);
      if (currIn) {
        if (!prevIn) output.push(intersect(prev, curr));
        output.push(curr);
      } else if (prevIn) {
        output.push(intersect(prev, curr));
      }
    }
  }
  return output;
}

export function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

// Closest point to `p` on the closed segment a-b.
export function projectPointOntoSegment(p: Point, a: Point, b: Point): Point {
  const abx = b.x - a.x;
  const aby = b.y - a.y;
  const lenSq = abx * abx + aby * aby;
  if (lenSq === 0) return a;
  const t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq, 0, 1);
  return { x: a.x + abx * t, y: a.y + aby * t };
}

// Minimum distance from a point to the nearest edge of a polygon boundary
// (not "is inside" — used for property-line setback checks).
export function distanceToPolygonBoundary(p: Point, polygon: Point[]): number {
  let min = Infinity;
  for (let i = 0; i < polygon.length; i++) {
    const a = polygon[i];
    const b = polygon[(i + 1) % polygon.length];
    const closest = projectPointOntoSegment(p, a, b);
    min = Math.min(min, distance(p, closest));
  }
  return min;
}

export function centerOf(t: Transform): Point {
  return { x: t.x, y: t.y };
}

// Closest point on (or in) an axis-aligned box to an external point — for a
// point outside the box this lands on its boundary, so a path can be anchored
// to a building's edge instead of visually running into its center.
export function nearestPointOnAabb(box: Bounds, target: Point): Point {
  return {
    x: clamp(target.x, box.minX, box.maxX),
    y: clamp(target.y, box.minY, box.maxY),
  };
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}

// Resizes a (possibly rotated) rect by dragging one of its 4 corners while
// keeping the diagonally opposite corner fixed in world space.
// cornerIndex follows rectCorners' order: 0=TL, 1=TR, 2=BR, 3=BL (local space).
export function resizeFromCorner(
  fixedCornerWorld: Point,
  cornerSign: Point, // sign (+/-1, +/-1) of the corner being DRAGGED, in local space
  rotationDeg: number,
  pointerWorld: Point,
  minWidth: number,
  minHeight: number,
): Transform {
  const rad = (rotationDeg * Math.PI) / 180;
  const cos = Math.cos(-rad);
  const sin = Math.sin(-rad);
  const dx = pointerWorld.x - fixedCornerWorld.x;
  const dy = pointerWorld.y - fixedCornerWorld.y;
  const localX = dx * cos - dy * sin;
  const localY = dx * sin + dy * cos;

  const width = Math.max(minWidth, Math.abs(localX));
  const height = Math.max(minHeight, Math.abs(localY));

  // Center sits half a diagonal away from the fixed corner, opposite the
  // dragged corner's sign, rotated back into world space.
  const halfW = width / 2;
  const halfH = height / 2;
  const centerLocalOffsetX = -cornerSign.x * halfW;
  const centerLocalOffsetY = -cornerSign.y * halfH;
  const fRad = (rotationDeg * Math.PI) / 180;
  const fCos = Math.cos(fRad);
  const fSin = Math.sin(fRad);
  const worldOffsetX = centerLocalOffsetX * fCos - centerLocalOffsetY * fSin;
  const worldOffsetY = centerLocalOffsetX * fSin + centerLocalOffsetY * fCos;

  return {
    x: fixedCornerWorld.x + worldOffsetX,
    y: fixedCornerWorld.y + worldOffsetY,
    width,
    height,
    rotationDeg,
  };
}
