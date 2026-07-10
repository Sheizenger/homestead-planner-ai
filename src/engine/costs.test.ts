import { describe, expect, it } from 'vitest';
import { createSampleProject } from '../data/sampleProject';
import { generateVariants } from './generate';
import { computeCostEstimate, findRegion } from './costs';

describe('computeCostEstimate', () => {
  const project = createSampleProject();
  const [variant] = generateVariants(project);

  it('computes land cost as plot area times the region land price', () => {
    const region = findRegion('us-national');
    const estimate = computeCostEstimate(variant, region);
    expect(estimate.landCostUsd).toBeCloseTo(variant.analytics.totalAreaM2 * region.landPricePerM2Usd, 5);
  });

  it('scales construction cost with the region labor index', () => {
    const cheap = computeCostEstimate(variant, findRegion('ru-national'));
    const expensive = computeCostEstimate(variant, findRegion('de-bavaria'));
    expect(expensive.constructionTotalUsd).toBeGreaterThan(cheap.constructionTotalUsd);
  });

  it('excludes locked (as-built) objects from construction cost', () => {
    const region = findRegion('us-national');
    const withLock = { ...variant, objects: variant.objects.map((o, i) => (i === 0 ? { ...o, locked: true } : o)) };
    const normal = computeCostEstimate(variant, region);
    const locked = computeCostEstimate(withLock, region);
    expect(locked.constructionTotalUsd).toBeLessThanOrEqual(normal.constructionTotalUsd);
  });

  it('totalUpfrontUsd is land plus construction', () => {
    const estimate = computeCostEstimate(variant, findRegion('custom'));
    expect(estimate.totalUpfrontUsd).toBeCloseTo(estimate.landCostUsd + estimate.constructionTotalUsd, 5);
  });
});
