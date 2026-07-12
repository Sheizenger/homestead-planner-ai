import { describe, expect, it } from 'vitest';
import type { Plot, WaterfrontEdge } from '../domain/types';
import { elevationAt, computeContourLines } from './elevation';

function makePlot(highEdge: WaterfrontEdge, dropM: number): Plot {
  return {
    id: 'p',
    boundary: [{ x: 0, y: 0 }, { x: 40, y: 0 }, { x: 40, y: 30 }, { x: 0, y: 30 }],
    northAngleDeg: 0,
    climateZone: 'temperate',
    terrainSlope: 'gentle',
    soilType: 'loam',
    waterSources: [],
    gridPower: true,
    elevation: { highEdge, dropM },
    existingObjects: [],
  };
}

describe('elevationAt', () => {
  it('returns 0 everywhere when no elevation is configured', () => {
    const plot = makePlot('north', 5);
    plot.elevation = undefined;
    expect(elevationAt(plot, { x: 20, y: 0 })).toBe(0);
    expect(elevationAt(plot, { x: 20, y: 30 })).toBe(0);
  });

  it('is highest at highEdge and 0 at the opposite edge, for each edge', () => {
    const north = makePlot('north', 10);
    expect(elevationAt(north, { x: 20, y: 0 })).toBeCloseTo(10);
    expect(elevationAt(north, { x: 20, y: 30 })).toBeCloseTo(0);

    const south = makePlot('south', 10);
    expect(elevationAt(south, { x: 20, y: 30 })).toBeCloseTo(10);
    expect(elevationAt(south, { x: 20, y: 0 })).toBeCloseTo(0);

    const west = makePlot('west', 10);
    expect(elevationAt(west, { x: 0, y: 15 })).toBeCloseTo(10);
    expect(elevationAt(west, { x: 40, y: 15 })).toBeCloseTo(0);

    const east = makePlot('east', 10);
    expect(elevationAt(east, { x: 40, y: 15 })).toBeCloseTo(10);
    expect(elevationAt(east, { x: 0, y: 15 })).toBeCloseTo(0);
  });

  it('interpolates linearly at the midpoint', () => {
    const plot = makePlot('north', 8);
    expect(elevationAt(plot, { x: 20, y: 15 })).toBeCloseTo(4);
  });
});

describe('computeContourLines', () => {
  it('returns no lines when there is no elevation configured', () => {
    const plot = makePlot('north', 0);
    plot.elevation = undefined;
    expect(computeContourLines(plot)).toEqual([]);
  });

  it('produces evenly spaced horizontal lines for a north/south grade', () => {
    const plot = makePlot('north', 10);
    const lines = computeContourLines(plot, 5);
    expect(lines.length).toBeGreaterThan(0);
    for (const line of lines) {
      expect(line.a.y).toBeCloseTo(line.b.y);
      expect(line.elevationM).toBeGreaterThan(0);
      expect(line.elevationM).toBeLessThan(10);
    }
  });

  it('produces vertical lines for an east/west grade', () => {
    const plot = makePlot('east', 10);
    const lines = computeContourLines(plot, 5);
    expect(lines.length).toBeGreaterThan(0);
    for (const line of lines) {
      expect(line.a.x).toBeCloseTo(line.b.x);
    }
  });
});
