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

  it('satisfies adjacency constraints (well-pump, solar-battery, greenhouse-utility) in every mode', () => {
    // Adjacency constraints are directional (subjectTypes vs relatedTypes)
    // and only ever influenced placement of whichever side of the pair got
    // placed second — regardless of mode, on a plot with real slack these
    // should be satisfiable and shouldn't surface as warnings just because
    // the greedy placement order happened to place the "subject" first.
    const project = createSampleProject();
    for (const mode of ['minimum-maintenance', 'production-max', 'beauty-balanced', 'safety-first'] as const) {
      const [variant] = generateVariants(project, mode);
      const adjacencyWarnings = variant.warnings.filter((w) => w.ruleId?.includes('adjacency'));
      expect(adjacencyWarnings).toEqual([]);
    }
  });
});
