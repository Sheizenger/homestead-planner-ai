import type { PlanObject, Plot, PathEntity, Fence } from '../domain/types';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { transformAabb } from './geometry';

// MVP simplification: access paths are straight segments from the house to
// each frequently-visited object's near edge, not a real pathfinder that
// routes around zone interiors — acceptable per PRD §13 risk mitigation.
export function synthesizePaths(objects: PlanObject[]): PathEntity[] {
  const house = objects.find((o) => o.typeId === 'house');
  if (!house) return [];
  const paths: PathEntity[] = [];
  for (const obj of objects) {
    if (obj.typeId === 'house') continue;
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry?.needsAccess) continue;
    paths.push({
      id: `path-${obj.id}`,
      points: [
        { x: house.transform.x, y: house.transform.y },
        { x: obj.transform.x, y: obj.transform.y },
      ],
      widthM: 1.2,
      surfaceType: 'gravel',
      category: 'access',
    });
  }
  return paths;
}

export function synthesizeFences(objects: PlanObject[], plot: Plot): Fence[] {
  const fences: Fence[] = [];
  fences.push({
    id: 'fence-perimeter',
    points: plot.boundary,
    fenceType: 'perimeter',
    gated: true,
  });
  for (const obj of objects) {
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry?.requiresFence) continue;
    const aabb = transformAabb(obj.transform);
    const pad = 0.6;
    fences.push({
      id: `fence-${obj.id}`,
      points: [
        { x: aabb.minX - pad, y: aabb.minY - pad },
        { x: aabb.maxX + pad, y: aabb.minY - pad },
        { x: aabb.maxX + pad, y: aabb.maxY + pad },
        { x: aabb.minX - pad, y: aabb.maxY + pad },
      ],
      fenceType: entry.category === 'animal' ? 'paddock' : entry.category === 'water' ? 'decorative' : 'garden',
      gated: false,
    });
  }
  return fences;
}
