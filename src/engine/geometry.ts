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

export function centerOf(t: Transform): Point {
  return { x: t.x, y: t.y };
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}
