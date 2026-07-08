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

export function rectFullyInsidePolygon(t: Transform, polygon: Point[]): boolean {
  return rectCorners(t).every((c) => pointInPolygon(c, polygon));
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
