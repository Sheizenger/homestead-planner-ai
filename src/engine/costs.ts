import type { LayoutVariant, ZoneCategory } from '../domain/types';
import {
  COST_REGIONS,
  OBJECT_COST_TABLE,
  OBJECT_CATEGORY_FALLBACK_COST,
  PATH_COST_PER_M2,
  FENCE_COST_PER_M,
  type CostRegion,
} from '../domain/costData';
import { ZONE_CATEGORY_ORDER, CATEGORY_STYLES } from '../domain/categories';
import { distance } from './geometry';

export interface CostRow {
  label: string;
  installUsd: number;
  annualUsd: number;
}

export interface CostEstimate {
  region: CostRegion;
  landAreaM2: number;
  landCostUsd: number;
  rows: CostRow[];
  constructionTotalUsd: number;
  annualMaintenanceTotalUsd: number;
  totalUpfrontUsd: number;
}

function pathLength(points: { x: number; y: number }[]): number {
  let len = 0;
  for (let i = 0; i < points.length - 1; i++) len += distance(points[i], points[i + 1]);
  return len;
}

export function computeCostEstimate(variant: LayoutVariant, region: CostRegion): CostEstimate {
  const landAreaM2 = variant.analytics.totalAreaM2;
  const landCostUsd = landAreaM2 * region.landPricePerM2Usd;

  const byCategory = new Map<ZoneCategory, { install: number; annual: number }>();
  const addToCategory = (category: ZoneCategory, install: number, annual: number) => {
    const row = byCategory.get(category) ?? { install: 0, annual: 0 };
    row.install += install;
    row.annual += annual;
    byCategory.set(category, row);
  };

  for (const obj of variant.objects) {
    if (obj.locked) continue; // as-built structures aren't a new expense
    const entry = OBJECT_COST_TABLE[obj.typeId] ?? OBJECT_CATEGORY_FALLBACK_COST[obj.category];
    if (!entry) continue;
    const areaM2 = obj.transform.width * obj.transform.height;
    const animalCount = typeof obj.metadata.animalCount === 'number' ? obj.metadata.animalCount : 0;
    const install =
      ((entry.installPerM2 ?? 0) * areaM2 + (entry.installFixed ?? 0)) * region.laborIndex;
    const annual =
      ((entry.annualPerM2 ?? 0) * areaM2 + (entry.annualFixed ?? 0) + (entry.annualPerAnimal ?? 0) * animalCount) *
      region.maintenanceIndex;
    addToCategory(obj.category as ZoneCategory, install, annual);
  }

  let pathInstall = 0;
  let pathAnnual = 0;
  for (const p of variant.paths) {
    const cost = PATH_COST_PER_M2[p.surfaceType] ?? PATH_COST_PER_M2.gravel;
    const areaM2 = pathLength(p.points) * p.widthM;
    pathInstall += cost.install * areaM2 * region.laborIndex;
    pathAnnual += cost.annual * areaM2 * region.maintenanceIndex;
  }

  let fenceInstall = 0;
  let fenceAnnual = 0;
  for (const f of variant.fences) {
    const cost = FENCE_COST_PER_M[f.fenceType] ?? FENCE_COST_PER_M.garden;
    const lengthM = pathLength([...f.points, f.points[0]]);
    fenceInstall += cost.install * lengthM * region.laborIndex;
    fenceAnnual += cost.annual * lengthM * region.maintenanceIndex;
  }

  const rows: CostRow[] = ZONE_CATEGORY_ORDER.filter((c) => byCategory.has(c)).map((category) => {
    const row = byCategory.get(category)!;
    return { label: CATEGORY_STYLES[category].label, installUsd: row.install, annualUsd: row.annual };
  });
  if (pathInstall > 0 || pathAnnual > 0) rows.push({ label: 'Paths', installUsd: pathInstall, annualUsd: pathAnnual });
  if (fenceInstall > 0 || fenceAnnual > 0) rows.push({ label: 'Fencing', installUsd: fenceInstall, annualUsd: fenceAnnual });

  const constructionTotalUsd = rows.reduce((sum, r) => sum + r.installUsd, 0);
  const annualMaintenanceTotalUsd = rows.reduce((sum, r) => sum + r.annualUsd, 0);

  return {
    region,
    landAreaM2,
    landCostUsd,
    rows,
    constructionTotalUsd,
    annualMaintenanceTotalUsd,
    totalUpfrontUsd: landCostUsd + constructionTotalUsd,
  };
}

export function findRegion(id: string): CostRegion {
  return COST_REGIONS.find((r) => r.id === id) ?? COST_REGIONS[0];
}
