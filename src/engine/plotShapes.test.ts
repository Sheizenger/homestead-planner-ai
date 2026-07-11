import { describe, expect, it } from 'vitest';
import { createSampleProject } from '../data/sampleProject';
import { generateVariants } from './generate';
import { buildLShapeBoundary, buildRectBoundary } from './plotShapes';
import { pointInPolygon, rectFullyInsidePolygon, segmentsIntersect, clipPolygonToRect } from './geometry';
import { transformAabb } from './geometry';

describe('buildLShapeBoundary', () => {
  it('produces a 6-point polygon with the requested corner notched out', () => {
    const boundary = buildLShapeBoundary(60, 35, 20, 15, 'ne');
    expect(boundary).toHaveLength(6);
    // The notched corner (top-right / NE) should not be part of the polygon.
    expect(pointInPolygon({ x: 55, y: 5 }, boundary)).toBe(false);
    // The rest of the rectangle should still be inside.
    expect(pointInPolygon({ x: 10, y: 10 }, boundary)).toBe(true);
    expect(pointInPolygon({ x: 10, y: 30 }, boundary)).toBe(true);
  });
});

describe('rectFullyInsidePolygon on concave boundaries', () => {
  const lPlot = buildLShapeBoundary(60, 35, 20, 15, 'ne');

  it('rejects a candidate rectangle whose corners are all inside the L but that bridges the notch', () => {
    // A wide rect spanning the full top edge would have its 4 corners inside
    // the L-shape's outer bounds check only if placed carelessly; here we
    // build one that bridges across the missing NE quadrant.
    const bridging = { x: 40, y: 7.5, width: 38, height: 15, rotationDeg: 0 };
    expect(rectFullyInsidePolygon(bridging, lPlot)).toBe(false);
  });

  it('accepts a candidate that stays within the remaining L-shaped area', () => {
    const inner = { x: 10, y: 10, width: 10, height: 10, rotationDeg: 0 };
    expect(rectFullyInsidePolygon(inner, lPlot)).toBe(true);
  });

  it('still accepts full-plot candidates on a plain rectangular boundary', () => {
    const rectPlot = buildRectBoundary(60, 35);
    const candidate = { x: 30, y: 17.5, width: 50, height: 25, rotationDeg: 0 };
    expect(rectFullyInsidePolygon(candidate, rectPlot)).toBe(true);
  });
});

describe('segmentsIntersect', () => {
  it('detects a genuine crossing', () => {
    expect(segmentsIntersect({ x: 0, y: 0 }, { x: 10, y: 10 }, { x: 0, y: 10 }, { x: 10, y: 0 })).toBe(true);
  });

  it('does not flag collinear/touching edges as a crossing', () => {
    expect(segmentsIntersect({ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 0 }, { x: 20, y: 0 })).toBe(false);
    expect(segmentsIntersect({ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 5, y: 0 }, { x: 5, y: 10 })).toBe(false);
  });
});

describe('clipPolygonToRect', () => {
  it('clips a polygon down to its intersection with a rectangle', () => {
    const square = [{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }, { x: 0, y: 10 }];
    const clipped = clipPolygonToRect(square, { minX: 5, minY: -5, maxX: 15, maxY: 15 });
    // Result should be the right half of the square: x in [5,10], y in [0,10].
    expect(clipped.every((p) => p.x >= 5 - 1e-6 && p.x <= 10 + 1e-6)).toBe(true);
    expect(clipped.length).toBeGreaterThanOrEqual(3);
  });
});

describe('generateVariants on a non-rectangular plot', () => {
  it('keeps every placed object fully within an L-shaped plot (none bridging the notch)', () => {
    const project = createSampleProject();
    project.plot.boundary = buildLShapeBoundary(60, 35, 20, 15, 'ne');
    const [variant] = generateVariants(project);
    expect(variant.objects.length).toBeGreaterThan(3);
    for (const obj of variant.objects) {
      const corners = [
        { x: obj.transform.x - obj.transform.width / 2, y: obj.transform.y - obj.transform.height / 2 },
        { x: obj.transform.x + obj.transform.width / 2, y: obj.transform.y - obj.transform.height / 2 },
        { x: obj.transform.x + obj.transform.width / 2, y: obj.transform.y + obj.transform.height / 2 },
        { x: obj.transform.x - obj.transform.width / 2, y: obj.transform.y + obj.transform.height / 2 },
      ];
      for (const c of corners) {
        expect(pointInPolygon(c, project.plot.boundary)).toBe(true);
      }
    }
  });

  it('computes the true polygon area, not the bounding-box area', () => {
    const project = createSampleProject();
    project.plot.boundary = buildLShapeBoundary(60, 35, 20, 15, 'ne');
    const [variant] = generateVariants(project);
    // Full rect would be 2100 m²; the L-shape removes a 20x15 = 300 m² notch.
    expect(variant.analytics.totalAreaM2).toBeCloseTo(1800, 0);
  });
});

// Keep transformAabb import used (sanity check on a trivial transform).
describe('transformAabb sanity', () => {
  it('computes an axis-aligned box for a 0deg transform', () => {
    const box = transformAabb({ x: 5, y: 5, width: 4, height: 2, rotationDeg: 0 });
    expect(box).toEqual({ minX: 3, minY: 4, maxX: 7, maxY: 6 });
  });
});
