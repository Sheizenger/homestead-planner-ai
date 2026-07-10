import type { PlanObject, Plot, PathEntity, Fence, Point, Transform } from '../domain/types';
import { OBJECT_LIBRARY, HOUSE_TYPE_IDS } from '../domain/objectLibrary';
import { transformAabb, projectPointOntoSegment, distance, nearestPointOnAabb, type Bounds } from './geometry';

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

// Nearest point on an object's own footprint to an external point — paths
// anchor to a building's edge, not its center, so a stroke doesn't visually
// run straight into the middle of a house or a large field.
function edgePoint(t: Transform, toward: Point): Point {
  return nearestPointOnAabb(transformAabb(t), toward);
}

// p1-p2 is always axis-aligned here (one leg of an L-shaped route), so the
// "does this leg cut through that box" test reduces to a 1D overlap check
// instead of needing a general segment/rect intersection.
function legHitsBox(p1: Point, p2: Point, box: Bounds): boolean {
  if (Math.abs(p1.y - p2.y) < 1e-6) {
    if (p1.y <= box.minY || p1.y >= box.maxY) return false;
    const xMin = Math.min(p1.x, p2.x);
    const xMax = Math.max(p1.x, p2.x);
    return xMax > box.minX && xMin < box.maxX;
  }
  if (p1.x <= box.minX || p1.x >= box.maxX) return false;
  const yMin = Math.min(p1.y, p2.y);
  const yMax = Math.max(p1.y, p2.y);
  return yMax > box.minY && yMin < box.maxY;
}

// Two-segment orthogonal route from a to b, elbowed at whichever of the two
// possible corners crosses fewer other objects' footprints — real garden
// paths bend around zones instead of cutting a straight diagonal across the
// whole plot. A lightweight stand-in for real pathfinding (MVP simplification,
// per PRD §13 risk mitigation), but a large improvement over one raw segment.
function routeAround(a: Point, b: Point, obstacles: Bounds[]): Point[] {
  if (Math.abs(a.x - b.x) < 0.3 || Math.abs(a.y - b.y) < 0.3) return [a, b];
  const elbowViaB = { x: b.x, y: a.y };
  const elbowViaA = { x: a.x, y: b.y };
  const crossings = (elbow: Point) =>
    obstacles.reduce((n, box) => n + (legHitsBox(a, elbow, box) ? 1 : 0) + (legHitsBox(elbow, b, box) ? 1 : 0), 0);
  const elbow = crossings(elbowViaB) <= crossings(elbowViaA) ? elbowViaB : elbowViaA;
  return [a, elbow, b];
}

// MVP simplification: paths route around obstacles with a single elbow, not
// a full pathfinder — acceptable per PRD §13 risk mitigation. The driveway
// (gate → garage, wide/paved) and entrance walk (gate → house, narrower) are
// distinguished from the narrower garden paths to other frequently-visited
// zones.
export function synthesizePaths(objects: PlanObject[], plot: Plot): PathEntity[] {
  const house = objects.find((o) => HOUSE_TYPE_IDS.includes(o.typeId));
  if (!house) return [];
  const houseCenter = { x: house.transform.x, y: house.transform.y };
  const gate = findGatePoint(plot.boundary, houseCenter);
  const garage = objects.find((o) => o.typeId === 'garage');
  const paths: PathEntity[] = [];

  const boxesExcept = (...ids: string[]) =>
    objects.filter((o) => !ids.includes(o.id)).map((o) => transformAabb(o.transform));

  if (garage && distance(gate, houseCenter) > 0.5) {
    const garageEdge = edgePoint(garage.transform, gate);
    paths.push({
      id: 'path-driveway',
      points: routeAround(gate, garageEdge, boxesExcept(garage.id)),
      widthM: 3,
      surfaceType: 'paved',
      category: 'service',
    });
  }

  const houseGateEdge = edgePoint(house.transform, gate);
  paths.push({
    id: 'path-entrance',
    points: routeAround(gate, houseGateEdge, boxesExcept(house.id)),
    widthM: 1.4,
    surfaceType: 'paved',
    category: 'access',
  });

  for (const obj of objects) {
    if (HOUSE_TYPE_IDS.includes(obj.typeId) || obj.typeId === 'garage') continue;
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry?.needsAccess || obj.metadata.roofMounted) continue;
    const objEdge = edgePoint(obj.transform, houseCenter);
    const houseEdge = edgePoint(house.transform, objEdge);
    paths.push({
      id: `path-${obj.id}`,
      points: routeAround(houseEdge, objEdge, boxesExcept(house.id, obj.id)),
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
