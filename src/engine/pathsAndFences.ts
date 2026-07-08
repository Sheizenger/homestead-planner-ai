import type { PlanObject, Plot, PathEntity, Fence, Point } from '../domain/types';
import { OBJECT_LIBRARY, HOUSE_TYPE_IDS } from '../domain/objectLibrary';
import { transformAabb, projectPointOntoSegment, distance } from './geometry';

// The "gate" is where the plot boundary is crossed to reach the house — the
// boundary edge with the largest average y (our south/road-facing convention,
// see placement.ts's house-siting bias), at the point closest to the house.
export function findGatePoint(boundary: Point[], houseCenter: Point): Point {
  let bestEdge: [Point, Point] | null = null;
  let bestY = -Infinity;
  for (let i = 0; i < boundary.length; i++) {
    const a = boundary[i];
    const b = boundary[(i + 1) % boundary.length];
    const midY = (a.y + b.y) / 2;
    if (midY > bestY) {
      bestY = midY;
      bestEdge = [a, b];
    }
  }
  if (!bestEdge) return houseCenter;
  return projectPointOntoSegment(houseCenter, bestEdge[0], bestEdge[1]);
}

// MVP simplification: paths are straight segments, not a real pathfinder that
// routes around zone interiors — acceptable per PRD §13 risk mitigation. The
// driveway (gate → garage, wide/paved) and entrance walk (gate → house,
// narrower) are distinguished from the narrower garden paths to other
// frequently-visited zones.
export function synthesizePaths(objects: PlanObject[], plot: Plot): PathEntity[] {
  const house = objects.find((o) => HOUSE_TYPE_IDS.includes(o.typeId));
  if (!house) return [];
  const houseCenter = { x: house.transform.x, y: house.transform.y };
  const gate = findGatePoint(plot.boundary, houseCenter);
  const garage = objects.find((o) => o.typeId === 'garage');
  const paths: PathEntity[] = [];

  if (garage && distance(gate, houseCenter) > 0.5) {
    paths.push({
      id: 'path-driveway',
      points: [gate, { x: garage.transform.x, y: garage.transform.y }],
      widthM: 3,
      surfaceType: 'paved',
      category: 'service',
    });
  }

  paths.push({
    id: 'path-entrance',
    points: [gate, houseCenter],
    widthM: 1.4,
    surfaceType: 'paved',
    category: 'access',
  });

  for (const obj of objects) {
    if (HOUSE_TYPE_IDS.includes(obj.typeId) || obj.typeId === 'garage') continue;
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry?.needsAccess) continue;
    paths.push({
      id: `path-${obj.id}`,
      points: [houseCenter, { x: obj.transform.x, y: obj.transform.y }],
      widthM: 1.1,
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
