import type { Point } from '../domain/types';

// Which corner of the width x height rectangle gets cut away to form the L.
export type PlotCorner = 'nw' | 'ne' | 'sw' | 'se';

export const PLOT_CORNERS: PlotCorner[] = ['nw', 'ne', 'sw', 'se'];

// Builds a 6-point L-shaped plot boundary by notching one corner out of a
// width x height rectangle (origin at 0,0, +y = south/road-facing, matching
// the convention used everywhere else in the engine).
export function buildLShapeBoundary(
  width: number,
  height: number,
  notchWidth: number,
  notchHeight: number,
  corner: PlotCorner,
): Point[] {
  const nw = Math.max(1, Math.min(notchWidth, width - 1));
  const nh = Math.max(1, Math.min(notchHeight, height - 1));
  switch (corner) {
    case 'se':
      return [
        { x: 0, y: 0 },
        { x: width, y: 0 },
        { x: width, y: height - nh },
        { x: width - nw, y: height - nh },
        { x: width - nw, y: height },
        { x: 0, y: height },
      ];
    case 'sw':
      return [
        { x: nw, y: 0 },
        { x: width, y: 0 },
        { x: width, y: height },
        { x: 0, y: height },
        { x: 0, y: height - nh },
        { x: nw, y: height - nh },
      ];
    case 'ne':
      return [
        { x: 0, y: 0 },
        { x: width - nw, y: 0 },
        { x: width - nw, y: nh },
        { x: width, y: nh },
        { x: width, y: height },
        { x: 0, y: height },
      ];
    case 'nw':
      return [
        { x: nw, y: 0 },
        { x: width, y: 0 },
        { x: width, y: height },
        { x: 0, y: height },
        { x: 0, y: nh },
        { x: nw, y: nh },
      ];
  }
}

export function buildRectBoundary(width: number, height: number): Point[] {
  return [
    { x: 0, y: 0 },
    { x: width, y: 0 },
    { x: width, y: height },
    { x: 0, y: height },
  ];
}
