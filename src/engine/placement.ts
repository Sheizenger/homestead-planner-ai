import type { Plot, PlanObject, Point, Transform, PlanningMode, ObjectCategory } from '../domain/types';
import { OBJECT_LIBRARY, HOUSE_TYPE_IDS, type ObjectLibraryEntry } from '../domain/objectLibrary';
import { CONSTRAINTS, BOUNDARY_SETBACKS } from '../domain/constraints';
import type { ProgramItem } from './sizing';
import {
  polygonBounds,
  polygonArea,
  rectFullyInsidePolygon,
  transformAabb,
  aabbOverlap,
  distance,
  distanceToPolygonBoundary,
} from './geometry';

// Fraction of the house footprint that's realistically usable for roof-mount
// PV (one south-facing slope, minus dormers/chimneys/valleys) — a coarse
// stand-in for a real roof-plane model.
const ROOF_USABLE_FRACTION = 0.5;

// Categories that read as "private/technical" and shouldn't crowd the direct
// house-to-gate approach (the one strip of yard every visitor actually sees
// and walks through).
const FRONT_AVOID_CATEGORIES: ObjectCategory[] = ['utility', 'water', 'energy', 'storage', 'animal', 'leisure'];
const SIDE_YARD_CATEGORIES: ObjectCategory[] = ['utility', 'water', 'energy'];

function matchesSetback(entry: ObjectLibraryEntry, appliesTo: string[]): boolean {
  return appliesTo.includes(entry.id) || appliesTo.includes(entry.category);
}

// Coarse placement tiers: structures/utilities go first as spatial anchors,
// then animals, then food zones, then incidental extras. Within a tier,
// items are placed largest-first (see sort below) so big fields claim open
// space before small beds nibble at what's left — plain priority-order
// placement otherwise starves large production-scaled fields that happen to
// sort late.
const PLACEMENT_TIERS: string[][] = [
  ['house', 'house-l'],
  ['garage', 'shed', 'barn', 'cellar', 'woodshed', 'workshop'],
  ['well', 'pump', 'septic', 'water-tank', 'rainwater-cistern', 'solar-array', 'battery-room', 'inverter-room', 'generator'],
  ['goat-shelter', 'goat-paddock', 'poultry-coop', 'apiary'],
  ['raised-beds', 'greenhouse', 'hydroponic-tower', 'vegetable-area', 'potato-area', 'grain-field', 'orchard-trees', 'berry-rows', 'vineyard'],
  ['compost', 'patio', 'pool', 'gazebo', 'banya', 'smokehouse'],
];

function tierOf(typeId: string): number {
  const idx = PLACEMENT_TIERS.findIndex((tier) => tier.includes(typeId));
  return idx === -1 ? PLACEMENT_TIERS.length : idx;
}

function mulberry32(seed: number) {
  let a = seed;
  return function rand() {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function matches(entry: ObjectLibraryEntry, list: string[]): boolean {
  return list.includes(entry.id) || list.includes(entry.category);
}

export interface PlacedResult {
  objects: PlanObject[];
  unplaced: ProgramItem[];
}

interface Candidate {
  transform: Transform;
  score: number;
  reasons: string[];
}

const MODE_WEIGHTS: Record<PlanningMode, { access: number; separation: number; sun: number; beauty: number }> = {
  'production-max': { access: 1, separation: 1, sun: 2.2, beauty: 0.2 },
  'minimum-maintenance': { access: 2.2, separation: 0.8, sun: 1, beauty: 0.3 },
  'beauty-balanced': { access: 1.2, separation: 1.1, sun: 1.2, beauty: 1.8 },
  'safety-first': { access: 1, separation: 2.2, sun: 1, beauty: 0.3 },
};

export function placeObjects(
  plot: Plot,
  program: ProgramItem[],
  mode: PlanningMode,
  seed: number,
): PlacedResult {
  const rand = mulberry32(seed);
  const bounds = polygonBounds(plot.boundary);
  const plotW = bounds.maxX - bounds.minX;
  const plotH = bounds.maxY - bounds.minY;
  const step = Math.max(1.2, Math.min(plotW, plotH) / 28);
  const weights = MODE_WEIGHTS[mode];

  // How much slack the plot has relative to the requested program: 0 means
  // the program nearly fills the plot (pack tight), higher means there's
  // real room to spare. Used to relax how hard objects cling to the house
  // and how tightly they pack against each other — the same program on a
  // much bigger plot should read as more spread out, not identically cramped.
  const plotArea = polygonArea(plot.boundary);
  const programArea = program.reduce((sum, item) => sum + item.width * item.height * item.count, 0);
  const slackRatio = plotArea > 0 ? Math.max(0, Math.min(1, (plotArea - programArea) / plotArea)) : 0;
  const spacingPad = 1.2 + slackRatio * 5;
  const comfortDist = 10 + slackRatio * 8;
  const compactPullScale = 0.15 * (1 - slackRatio * 0.75);
  const layout = { spacingPad, comfortDist, compactPullScale };

  const sorted = [...program].sort((a, b) => {
    const tierDiff = tierOf(a.typeId) - tierOf(b.typeId);
    if (tierDiff !== 0) return tierDiff;
    return b.width * b.height - a.width * a.height; // largest-first within a tier
  });

  const placed: PlanObject[] = [...plot.existingObjects.map((e) => ({
    id: e.id,
    typeId: e.type,
    category: (OBJECT_LIBRARY[e.type]?.category ?? 'residential') as ObjectCategory,
    transform: e.transform,
    label: e.label,
    locked: true,
    layerId: (OBJECT_LIBRARY[e.type]?.category ?? 'residential') as ObjectCategory,
    metadata: {},
  }))];
  const unplaced: ProgramItem[] = [];

  let houseCenter = placed.find((p) => HOUSE_TYPE_IDS.includes(p.typeId))?.transform;

  for (const item of sorted) {
    const entry = OBJECT_LIBRARY[item.typeId];
    if (!entry) continue;
    const width = item.width;
    const height = item.height;

    if (item.typeId === 'solar-array' && houseCenter) {
      const roofArea = houseCenter.width * houseCenter.height * ROOF_USABLE_FRACTION;
      if (width * height <= roofArea) {
        const roofW = Math.min(width, houseCenter.width * 0.8);
        const roofH = Math.min(height, houseCenter.height * 0.8);
        placed.push({
          id: `obj-${item.typeId}-${placed.length}-${Math.floor(rand() * 1e6)}`,
          typeId: item.typeId,
          category: entry.category,
          transform: {
            x: houseCenter.x + (houseCenter.width - roofW) * 0.2,
            y: houseCenter.y - (houseCenter.height - roofH) * 0.2,
            width: roofW,
            height: roofH,
            rotationDeg: houseCenter.rotationDeg,
          },
          label: entry.label,
          locked: false,
          layerId: entry.category,
          metadata: { ...item.metadata, roofMounted: true },
          rationale: `${entry.label}: roof-mounted on the house, saving yard space and keeping DC wiring runs short.`,
        });
        continue;
      }
    }

    let best = searchBestCandidate(plot, bounds, step, width, height, entry, placed, houseCenter, weights, rand, layout);
    for (const shrink of [0.8, 0.6, 0.45]) {
      if (best) break;
      best = searchBestCandidate(plot, bounds, step, width * shrink, height * shrink, entry, placed, houseCenter, weights, rand, layout);
    }
    if (!best) {
      unplaced.push(item);
      continue;
    }

    const obj: PlanObject = {
      id: `obj-${item.typeId}-${placed.length}-${Math.floor(rand() * 1e6)}`,
      typeId: item.typeId,
      category: entry.category,
      transform: best.transform,
      label: entry.label,
      locked: false,
      layerId: entry.category,
      metadata: item.metadata,
      rationale: buildRationale(entry, best.reasons),
    };
    placed.push(obj);
    if (HOUSE_TYPE_IDS.includes(item.typeId)) houseCenter = obj.transform;
  }

  return { objects: placed, unplaced };
}

function searchBestCandidate(
  plot: Plot,
  bounds: ReturnType<typeof polygonBounds>,
  step: number,
  width: number,
  height: number,
  entry: ObjectLibraryEntry,
  placed: PlanObject[],
  houseCenter: Transform | undefined,
  weights: { access: number; separation: number; sun: number; beauty: number },
  rand: () => number,
  layout: { spacingPad: number; comfortDist: number; compactPullScale: number },
): Candidate | null {
  const orientations = width === height ? [0] : [0, 90];
  let best: Candidate | null = null;

  for (let x = bounds.minX + width / 2; x <= bounds.maxX - width / 2; x += step) {
    for (let y = bounds.minY + height / 2; y <= bounds.maxY - height / 2; y += step) {
      for (const rot of orientations) {
        const w = rot === 90 ? height : width;
        const h = rot === 90 ? width : height;
        const transform: Transform = { x: x + (rand() - 0.5) * step * 0.3, y: y + (rand() - 0.5) * step * 0.3, width: w, height: h, rotationDeg: 0 };
        if (!rectFullyInsidePolygon(transform, plot.boundary)) continue;

        const aabb = transformAabb(transform);
        const overlaps = placed.some((p) => aabbOverlap(aabb, transformAabb(p.transform), layout.spacingPad));
        if (overlaps) continue;

        const hardViolation = CONSTRAINTS.some((c) => {
          if (!c.hard || (c.kind !== 'separation' && c.kind !== 'safety') || !c.minDistance) return false;
          if (!matches(entry, c.subjectTypes)) return false;
          return placed.some((p) => {
            const otherEntry = OBJECT_LIBRARY[p.typeId];
            if (!otherEntry || !matches(otherEntry, c.relatedTypes)) return false;
            return distance(transform, p.transform) < c.minDistance!;
          });
        });
        if (hardViolation) continue;

        const { score, reasons } = scoreCandidate(transform, entry, placed, houseCenter, bounds, weights, plot.boundary, layout);
        if (!best || score > best.score) best = { transform, score, reasons };
      }
    }
  }
  return best;
}

function scoreCandidate(
  transform: Transform,
  entry: ObjectLibraryEntry,
  placed: PlanObject[],
  houseCenter: Transform | undefined,
  bounds: ReturnType<typeof polygonBounds>,
  weights: { access: number; separation: number; sun: number; beauty: number },
  boundary: Point[],
  layout: { spacingPad: number; comfortDist: number; compactPullScale: number },
): { score: number; reasons: string[] } {
  let score = 0;
  const reasons: string[] = [];

  if (houseCenter && !HOUSE_TYPE_IDS.includes(entry.id)) {
    const d = distance(transform, houseCenter);
    if (entry.needsAccess) {
      // Diminishing returns on closeness: within "comfortable walking
      // distance" further shaving off a meter barely matters, so the search
      // doesn't fight to snap every frequently-visited object flush against
      // the house wall — beyond it, distance costs more steeply. This is
      // what actually lets a bigger plot (same objects) read as more spread
      // out instead of identically huddled around the house.
      const penalty = d <= layout.comfortDist ? d * 0.3 : layout.comfortDist * 0.3 + (d - layout.comfortDist) * 1.4;
      score -= penalty * weights.access;
      if (d < layout.comfortDist) reasons.push('close to the house for frequent access');
    } else {
      score -= d * weights.access * layout.compactPullScale; // mild preference for compactness even for low-visit zones
    }

    // Sector siting: a house has a road-facing front (the direct approach
    // from the gate, kept clear for entry) and a private back yard on the
    // opposite side, per the same south/road-facing convention used for
    // house placement itself and for the gate.
    const relX = transform.x - houseCenter.x;
    const relY = transform.y - houseCenter.y; // + = toward the gate/road, - = away from it (back yard)

    // Layout convention, not an aesthetic-mode preference — kept independent
    // of weights.beauty so septic-behind-the-house or patio-by-the-potatoes
    // doesn't come back the moment someone picks Production-Maximizing.
    const sectorWeight = 0.7 + weights.separation * 0.15;

    if (entry.category === 'leisure') {
      // Outdoor living space belongs in the private back yard, not staged
      // between the house and the road.
      if (relY < 0) {
        score += Math.min(-relY, 10) * sectorWeight;
        reasons.push('sited in the private back yard');
      } else {
        score -= relY * sectorWeight * 0.8;
      }
    } else if (FRONT_AVOID_CATEGORIES.includes(entry.category)) {
      // Keep the direct house-to-gate approach clear of clutter (sheds,
      // septic fields, animal pens, etc. don't belong in the front yard).
      const frontHalfWidth = houseCenter.width / 2 + 2;
      if (relY > 1 && Math.abs(relX) < frontHalfWidth) {
        score -= 15 * sectorWeight;
      }
    }

    if (SIDE_YARD_CATEGORIES.includes(entry.category)) {
      // Technical/utility items (septic, well, water tank, solar, battery)
      // conventionally sit in a side yard, not dead-center behind the house.
      score += Math.min(Math.abs(relX), 12) * sectorWeight * 0.3;
      if (Math.abs(relX) < houseCenter.width * 0.25) {
        score -= 6 * sectorWeight;
      }
    }
  } else if (!houseCenter) {
    // House placement: bias toward the "front" (larger y = south/road side by convention).
    score += (transform.y - bounds.minY) * 1.5;
    reasons.push('positioned toward the plot’s road-facing side');
  }

  for (const setback of BOUNDARY_SETBACKS) {
    if (!matchesSetback(entry, setback.appliesTo)) continue;
    const d = distanceToPolygonBoundary(transform, boundary);
    if (d < setback.minDistanceM) {
      score -= (setback.minDistanceM - d) * weights.separation * 2;
    } else {
      reasons.push('kept clear of the property line');
    }
  }

  for (const c of CONSTRAINTS) {
    if (!matches(entry, c.subjectTypes)) continue;
    for (const p of placed) {
      const otherEntry = OBJECT_LIBRARY[p.typeId];
      if (!otherEntry || !matches(otherEntry, c.relatedTypes)) continue;
      const d = distance(transform, p.transform);
      if ((c.kind === 'separation' || c.kind === 'safety') && c.minDistance && d < c.minDistance) {
        score -= (c.minDistance - d) * weights.separation;
        reasons.push(`kept apart from ${p.label.toLowerCase()}`);
      }
      if (c.kind === 'adjacency' && c.maxDistance) {
        if (d > c.maxDistance) score -= (d - c.maxDistance) * weights.access * 0.5;
        else {
          score += (c.maxDistance - d) * weights.access * 0.3;
          reasons.push(`kept near ${p.label.toLowerCase()}`);
        }
      }
    }
  }

  if (entry.sunNeed === 'full') {
    const southness = transform.y - bounds.minY;
    score += southness * weights.sun * 0.6;
    const shaded = placed.some((p) => {
      const otherEntry = OBJECT_LIBRARY[p.typeId];
      if (!otherEntry || !['residential', 'food-perennial', 'storage'].includes(otherEntry.category)) return false;
      const isNorthOfCandidate = p.transform.y < transform.y;
      const withinShadowBand = Math.abs(p.transform.x - transform.x) < (p.transform.width + transform.width);
      const closeEnough = transform.y - p.transform.y < p.transform.height * 2.5;
      return isNorthOfCandidate && withinShadowBand && closeEnough;
    });
    if (shaded) score -= 40 * weights.sun;
    else reasons.push('full southern sun exposure, clear of shade');
  }

  if (entry.noiseLevel === 'loud' || entry.odorLevel === 'strong') {
    const distToBoundary = Math.min(
      transform.x - bounds.minX,
      bounds.maxX - transform.x,
      transform.y - bounds.minY,
      bounds.maxY - transform.y,
    );
    score += distToBoundary * weights.separation * 0.3;
  }

  if (weights.beauty > 1) {
    const alignsWithExisting = placed.some(
      (p) => Math.abs(p.transform.x - transform.x) < 1.5 || Math.abs(p.transform.y - transform.y) < 1.5,
    );
    if (alignsWithExisting) {
      score += 12 * weights.beauty;
      reasons.push('aligned with existing zones for visual order');
    }
  }

  return { score, reasons };
}

function buildRationale(entry: ObjectLibraryEntry, reasons: string[]): string {
  if (reasons.length === 0) return `${entry.label} placed within available space.`;
  const unique = [...new Set(reasons)].slice(0, 2);
  return `${entry.label}: ${unique.join('; ')}.`;
}
