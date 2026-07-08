import type { AnalyticsSnapshot, PlanObject, Plot, Zone, ZoneCategory } from '../domain/types';
import { ZONE_CATEGORY_ORDER } from '../domain/categories';
import { polygonArea } from './geometry';

const FOOD_CATEGORIES: ZoneCategory[] = ['food-annual', 'food-perennial', 'greenhouse'];
const ANNUAL_MAINTENANCE_WEIGHT: Partial<Record<ZoneCategory, number>> = {
  'food-annual': 3,
  animal: 3.5,
  greenhouse: 2.5,
  'food-perennial': 1,
  residential: 0.5,
  energy: 1,
  water: 0.5,
  utility: 1,
  storage: 0.5,
  leisure: 0.5,
  access: 0.2,
  'future-expansion': 0,
};

export function computeAnalytics(objects: PlanObject[], zones: Zone[], plot: Plot): AnalyticsSnapshot {
  const totalAreaM2 = polygonArea(plot.boundary);
  const byCategoryMap = new Map<ZoneCategory, number>();

  for (const obj of objects) {
    if (!ZONE_CATEGORY_ORDER.includes(obj.category as ZoneCategory)) continue;
    const cat = obj.category as ZoneCategory;
    const area = obj.transform.width * obj.transform.height;
    byCategoryMap.set(cat, (byCategoryMap.get(cat) ?? 0) + area);
  }
  for (const zone of zones) {
    byCategoryMap.set(zone.category, (byCategoryMap.get(zone.category) ?? 0) + polygonArea(zone.boundary));
  }

  const allocatedAreaM2 = [...byCategoryMap.values()].reduce((a, b) => a + b, 0);
  const unallocatedAreaM2 = Math.max(0, totalAreaM2 - allocatedAreaM2);

  const byCategory = ZONE_CATEGORY_ORDER.filter((c) => byCategoryMap.has(c)).map((category) => {
    const areaM2 = byCategoryMap.get(category) ?? 0;
    return { category, areaM2, percent: totalAreaM2 > 0 ? (areaM2 / totalAreaM2) * 100 : 0 };
  });

  const foodArea = FOOD_CATEGORIES.reduce((sum, c) => sum + (byCategoryMap.get(c) ?? 0), 0);
  const estimatedFoodProductionScore = totalAreaM2 > 0 ? Math.min(100, (foodArea / totalAreaM2) * 220) : 0;

  const maintenanceRaw = [...byCategoryMap.entries()].reduce(
    (sum, [cat, area]) => sum + area * (ANNUAL_MAINTENANCE_WEIGHT[cat] ?? 1),
    0,
  );
  const maintenanceComplexityScore = totalAreaM2 > 0 ? Math.min(100, (maintenanceRaw / totalAreaM2) * 12) : 0;

  return {
    totalAreaM2,
    allocatedAreaM2,
    unallocatedAreaM2,
    byCategory,
    estimatedFoodProductionScore,
    maintenanceComplexityScore,
    computedAt: new Date().toISOString(),
  };
}
