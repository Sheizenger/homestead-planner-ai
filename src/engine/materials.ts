import type { Fence, LayoutVariant, Point } from '../domain/types';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { distance } from './geometry';

function polylineLength(points: Point[]): number {
  let len = 0;
  for (let i = 0; i < points.length - 1; i++) len += distance(points[i], points[i + 1]);
  return len;
}

export interface FenceQuantity {
  fenceType: Fence['fenceType'];
  lengthM: number;
}

export type PathGroup = 'driveway' | 'walkway' | 'gardenPath';

export interface PathQuantity {
  group: PathGroup;
  lengthM: number;
  widthM: number;
  areaM2: number;
}

export interface StructureQuantity {
  typeId: string;
  label: string;
  widthM: number;
  heightM: number;
  areaM2: number;
}

export interface MaterialsTakeoff {
  fences: FenceQuantity[];
  totalFenceLengthM: number;
  paths: PathQuantity[];
  totalPavedAreaM2: number;
  totalGravelAreaM2: number;
  structures: StructureQuantity[];
}

// A real bill-of-quantities view of the plan — how many meters of each
// fence type, how many square meters of paved driveway/walkway vs gravel
// path, and each structure's footprint — as opposed to computeCostEstimate,
// which turns the same underlying geometry straight into money and never
// exposes the raw quantities a contractor would actually order materials
// against.
export function computeMaterialsTakeoff(variant: LayoutVariant): MaterialsTakeoff {
  const fenceByType = new Map<Fence['fenceType'], number>();
  for (const f of variant.fences) {
    const lengthM = polylineLength([...f.points, f.points[0]]);
    fenceByType.set(f.fenceType, (fenceByType.get(f.fenceType) ?? 0) + lengthM);
  }
  const fences = [...fenceByType.entries()].map(([fenceType, lengthM]) => ({ fenceType, lengthM }));
  const totalFenceLengthM = fences.reduce((s, f) => s + f.lengthM, 0);

  const pathGroups = new Map<PathGroup, { lengthM: number; widthM: number }>();
  for (const p of variant.paths) {
    const group: PathGroup = p.category === 'service' ? 'driveway' : p.surfaceType === 'paved' ? 'walkway' : 'gardenPath';
    const lengthM = polylineLength(p.points);
    const existing = pathGroups.get(group);
    if (existing) existing.lengthM += lengthM;
    else pathGroups.set(group, { lengthM, widthM: p.widthM });
  }
  const paths: PathQuantity[] = [...pathGroups.entries()].map(([group, v]) => ({
    group,
    lengthM: v.lengthM,
    widthM: v.widthM,
    areaM2: v.lengthM * v.widthM,
  }));
  const totalPavedAreaM2 = paths.filter((p) => p.group !== 'gardenPath').reduce((s, p) => s + p.areaM2, 0);
  const totalGravelAreaM2 = paths.filter((p) => p.group === 'gardenPath').reduce((s, p) => s + p.areaM2, 0);

  const structures: StructureQuantity[] = variant.objects
    .map((o) => ({
      typeId: o.typeId,
      label: OBJECT_LIBRARY[o.typeId]?.label ?? o.typeId,
      widthM: o.transform.width,
      heightM: o.transform.height,
      areaM2: o.transform.width * o.transform.height,
    }))
    .sort((a, b) => b.areaM2 - a.areaM2);

  return { fences, totalFenceLengthM, paths, totalPavedAreaM2, totalGravelAreaM2, structures };
}
