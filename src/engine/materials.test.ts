import { describe, expect, it } from 'vitest';
import { createSampleProject } from '../data/sampleProject';
import { generateVariants } from './generate';
import { computeMaterialsTakeoff } from './materials';

describe('computeMaterialsTakeoff', () => {
  it('reports fence, path, and structure quantities that add up sensibly', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const takeoff = computeMaterialsTakeoff(variant);

    expect(takeoff.fences.length).toBeGreaterThan(0);
    expect(takeoff.totalFenceLengthM).toBeGreaterThan(0);
    // Perimeter fence alone should roughly match the plot's perimeter (60+35)*2 = 190 m.
    const perimeter = takeoff.fences.find((f) => f.fenceType === 'perimeter');
    expect(perimeter?.lengthM).toBeCloseTo(190, -1);

    expect(takeoff.paths.length).toBeGreaterThan(0);
    expect(takeoff.totalPavedAreaM2 + takeoff.totalGravelAreaM2).toBeGreaterThan(0);
    for (const p of takeoff.paths) {
      expect(p.areaM2).toBeCloseTo(p.lengthM * p.widthM, 5);
    }

    expect(takeoff.structures.length).toBe(variant.objects.length);
    expect(takeoff.structures.some((s) => s.typeId === 'house')).toBe(true);
    // Sorted largest-first.
    for (let i = 1; i < takeoff.structures.length; i++) {
      expect(takeoff.structures[i - 1].areaM2).toBeGreaterThanOrEqual(takeoff.structures[i].areaM2);
    }
  });
});
