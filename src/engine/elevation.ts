import type { Plot, Point } from '../domain/types';
import { polygonBounds } from './geometry';

// Linear-grade elevation model: 0 m at the boundary edge opposite
// `highEdge`, rising to `dropM` at `highEdge` itself, interpolated linearly
// in between. Returns 0 when the plot has no configured elevation.
export function elevationAt(plot: Plot, point: Point): number {
  const el = plot.elevation;
  if (!el || el.dropM <= 0) return 0;
  const b = polygonBounds(plot.boundary);
  const spanY = Math.max(1e-6, b.maxY - b.minY);
  const spanX = Math.max(1e-6, b.maxX - b.minX);
  switch (el.highEdge) {
    case 'north':
      return el.dropM * ((b.maxY - point.y) / spanY);
    case 'south':
      return el.dropM * ((point.y - b.minY) / spanY);
    case 'west':
      return el.dropM * ((b.maxX - point.x) / spanX);
    case 'east':
      return el.dropM * ((point.x - b.minX) / spanX);
  }
}

export interface ContourLine {
  elevationM: number;
  a: Point;
  b: Point;
}

// Rounds a raw interval up to a "nice" round number (1/2/5 x a power of 10)
// so contour labels read like "2 m", "5 m", "10 m" rather than "3.7 m".
function niceInterval(raw: number): number {
  if (raw <= 0) return 1;
  const pow = 10 ** Math.floor(Math.log10(raw));
  const norm = raw / pow;
  const nice = norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10;
  return nice * pow;
}

// Contour lines for a linear-grade plot are just straight lines parallel to
// the low/high edges, evenly spaced by elevation — clipped to the plot's
// bounding box, which is a fine visual approximation even for a concave
// custom polygon (the lines simply extend a little past the true edge in a
// notch, same tradeoff already accepted for grid lines).
export function computeContourLines(plot: Plot, targetCount = 5): ContourLine[] {
  const el = plot.elevation;
  if (!el || el.dropM <= 0) return [];
  const bounds = polygonBounds(plot.boundary);
  const interval = niceInterval(el.dropM / targetCount);
  const lines: ContourLine[] = [];
  for (let level = interval; level < el.dropM - 1e-6; level += interval) {
    const t = level / el.dropM;
    let a: Point;
    let b: Point;
    switch (el.highEdge) {
      case 'north': {
        const y = bounds.maxY - t * (bounds.maxY - bounds.minY);
        a = { x: bounds.minX, y };
        b = { x: bounds.maxX, y };
        break;
      }
      case 'south': {
        const y = bounds.minY + t * (bounds.maxY - bounds.minY);
        a = { x: bounds.minX, y };
        b = { x: bounds.maxX, y };
        break;
      }
      case 'west': {
        const x = bounds.maxX - t * (bounds.maxX - bounds.minX);
        a = { x, y: bounds.minY };
        b = { x, y: bounds.maxY };
        break;
      }
      case 'east': {
        const x = bounds.minX + t * (bounds.maxX - bounds.minX);
        a = { x, y: bounds.minY };
        b = { x, y: bounds.maxY };
        break;
      }
    }
    lines.push({ elevationM: level, a, b });
  }
  return lines;
}
