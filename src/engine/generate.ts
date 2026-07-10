import { v4 as uuid } from 'uuid';
import type { LayoutVariant, PlanningMode, Plot, PlanObject, Project, Zone } from '../domain/types';
import { parseFreeText, mergeFreeTextIntoStructured } from './textParser';
import { buildProgram } from './sizing';
import { placeObjects } from './placement';
import { synthesizePaths, synthesizeFences } from './pathsAndFences';
import { computeAnalytics } from './analytics';
import { computeWarnings } from './warnings';
import { polygonBounds, transformAabb, aabbOverlap, polygonArea } from './geometry';

const STRATEGY_LABELS: Record<PlanningMode, string> = {
  'minimum-maintenance': 'Compact & Efficient',
  'production-max': 'Production-Maximizing',
  'beauty-balanced': 'Beauty-Balanced',
  'safety-first': 'Safety-First',
};

export function generateVariants(project: Project, selectedMode?: PlanningMode): LayoutVariant[] {
  const modes: PlanningMode[] = ['minimum-maintenance', 'production-max', 'beauty-balanced'];
  if (selectedMode && !modes.includes(selectedMode)) modes[0] = selectedMode;
  return modes.map((mode, i) => generateVariant(project, mode, 42 + i * 17));
}

export function generateVariant(project: Project, mode: PlanningMode, seed: number): LayoutVariant {
  const extraction = parseFreeText(project.brief.freeText);
  const mergedInputs = mergeFreeTextIntoStructured(project.brief.structuredInputs, extraction);
  const program = buildProgram(mergedInputs, mode);
  const { objects, unplaced } = placeObjects(project.plot, program, mode, seed);
  const paths = synthesizePaths(objects, project.plot);
  const fences = synthesizeFences(objects, project.plot);
  const zones = buildFutureExpansionZone(project.plot, objects, mode);
  const analytics = computeAnalytics(objects, zones, project.plot);
  const warnings = computeWarnings(
    objects,
    fences,
    analytics,
    project.plot,
    mergedInputs.householdSize,
    mergedInputs.climateZone,
    mergedInputs.crops,
  );

  for (const item of unplaced) {
    warnings.unshift({
      id: `warn-unplaced-${item.typeId}-${uuid().slice(0, 8)}`,
      severity: 'critical',
      message: `Could not fit "${item.typeId.replace(/-/g, ' ')}" anywhere on the plot without violating hard constraints or overlapping existing zones. Consider a larger plot or a smaller program.`,
      messageKey: 'warning.unplaced',
      messageParams: { itemType: item.typeId },
      ruleId: 'capacity-overflow',
      objectIds: [],
    });
  }

  return {
    id: uuid(),
    strategyLabel: STRATEGY_LABELS[mode],
    mode,
    seed,
    zones,
    objects,
    paths,
    fences,
    utilityNodes: [],
    analytics,
    warnings,
    history: { past: [], future: [] },
  };
}

function buildFutureExpansionZone(plot: Plot, objects: PlanObject[], mode: PlanningMode): Zone[] {
  if (mode === 'production-max') return [];
  const bounds = polygonBounds(plot.boundary);
  const plotArea = polygonArea(plot.boundary);
  const reserveShare = mode === 'safety-first' ? 0.06 : mode === 'beauty-balanced' ? 0.08 : 0.1;
  const baseAspect = (bounds.maxX - bounds.minX) / Math.max(1, bounds.maxY - bounds.minY);

  // Scan a grid of candidate positions (favoring corners via scan order) at
  // full size, then progressively smaller, rather than only checking the 4
  // exact corners — a tightly packed plot rarely has a free spot exactly there.
  // Free space left over by greedy placement is often a narrow strip rather
  // than shaped like the plot itself, so both the plot-aspect rectangle and
  // its 90°-rotated counterpart are tried.
  for (const shrink of [1, 0.7, 0.5, 0.35, 0.2]) {
    const targetArea = plotArea * reserveShare * shrink;
    for (const aspect of [baseAspect, 1 / baseAspect]) {
      const w = Math.sqrt(targetArea * aspect);
      const h = targetArea / w;
      if (w < 2 || h < 2 || w > bounds.maxX - bounds.minX || h > bounds.maxY - bounds.minY) continue;

      const stepX = Math.max(1, (bounds.maxX - bounds.minX - w) / 10);
      const stepY = Math.max(1, (bounds.maxY - bounds.minY - h) / 10);
      const candidates: { x: number; y: number }[] = [];
      for (let x = bounds.minX + w / 2; x <= bounds.maxX - w / 2 + 0.01; x += stepX) {
        for (let y = bounds.minY + h / 2; y <= bounds.maxY - h / 2 + 0.01; y += stepY) {
          candidates.push({ x, y });
        }
      }
      // Prefer positions closer to a corner of the plot (visually a "reserved edge").
      candidates.sort((a, b) => cornerDistance(a, bounds) - cornerDistance(b, bounds));

      for (const c of candidates) {
        const aabb = { minX: c.x - w / 2, minY: c.y - h / 2, maxX: c.x + w / 2, maxY: c.y + h / 2 };
        const overlaps = objects.some((o) => aabbOverlap(aabb, transformAabb(o.transform), 1));
        if (overlaps) continue;
        return [
          {
            id: 'zone-future-expansion',
            category: 'future-expansion',
            boundary: [
              { x: aabb.minX, y: aabb.minY },
              { x: aabb.maxX, y: aabb.minY },
              { x: aabb.maxX, y: aabb.maxY },
              { x: aabb.minX, y: aabb.maxY },
            ],
            label: 'Future Expansion',
            metadata: { reservedForm: 'user-defined future use' },
            locked: false,
          },
        ];
      }
    }
  }
  return [];
}

function cornerDistance(p: { x: number; y: number }, bounds: ReturnType<typeof polygonBounds>): number {
  const corners = [
    { x: bounds.minX, y: bounds.minY },
    { x: bounds.maxX, y: bounds.minY },
    { x: bounds.minX, y: bounds.maxY },
    { x: bounds.maxX, y: bounds.maxY },
  ];
  return Math.min(...corners.map((c) => Math.hypot(c.x - p.x, c.y - p.y)));
}
