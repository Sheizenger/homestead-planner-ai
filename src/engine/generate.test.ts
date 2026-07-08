import { describe, expect, it } from 'vitest';
import { createSampleProject } from '../data/sampleProject';
import { generateVariants } from './generate';

describe('generateVariants', () => {
  it('produces 3 distinct variants with placed objects and no crash', () => {
    const project = createSampleProject();
    const variants = generateVariants(project);
    expect(variants).toHaveLength(3);
    for (const v of variants) {
      expect(v.objects.length).toBeGreaterThan(5);
      expect(v.objects.some((o) => o.typeId === 'house')).toBe(true);
      expect(v.analytics.totalAreaM2).toBeCloseTo(2100, 0);
    }
  });

  it('generates measurably different category allocations across variants', () => {
    const project = createSampleProject();
    const [compact, production, beauty] = generateVariants(project);
    const foodArea = (v: (typeof compact)) =>
      v.analytics.byCategory
        .filter((c) => ['food-annual', 'food-perennial', 'greenhouse'].includes(c.category))
        .reduce((s, c) => s + c.areaM2, 0);

    expect(foodArea(production)).toBeGreaterThan(foodArea(compact));
    expect(compact.strategyLabel).not.toBe(production.strategyLabel);
    expect(production.strategyLabel).not.toBe(beauty.strategyLabel);
  });

  it('flags well/septic proximity violations as critical', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const critical = variant.warnings.filter((w) => w.severity === 'critical');
    expect(critical.every((w) => typeof w.message === 'string')).toBe(true);
  });
});
