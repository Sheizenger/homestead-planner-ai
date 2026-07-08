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
  const paths = synthesizePaths(objects);
  const fences = synthesizeFences(objects, project.plot);
  const zones = buildFutureExpansionZone(project.plot, objects, mode);
  const analytics = computeAnalytics(objects, zones, project.plot);
  const warnings = computeWarnings(objects, fences, analytics);

  for (const item of unplaced) {
    warnings.unshift({
      id: `warn-unplaced-${item.typeId}-${uuid().slice(0, 8)}`,
      severity: 'critical',
      message: `Could not fit "${item.typeId.replace(/-/g, ' ')}" anywhere on the plot without violating hard constraints or overlapping existing zones. Consider a larger plot or a smaller program.`,
      ruleId: 'capacity-overflow',
      objectIds: [],
    });
  }

  const rationaleSummary = objects.filter((o) => o.rationale && !o.locked).map((o) => o.rationale!);

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
    rationaleSummary,
    history: { past: [], future: [] },
  };
}

function buildFutureExpansionZone(plot: Plot, objects: PlanObject[], mode: PlanningMode): Zone[] {
  if (mode === 'production-max') return [];
  const bounds = polygonBounds(plot.boundary);
  const plotArea = polygonArea(plot.boundary);
  const reserveShare = mode === 'safety-first' ? 0.06 : mode === 'beauty-balanced' ? 0.08 : 0.1;
  const targetArea = plotArea * reserveShare;
  const aspect = (bounds.maxX - bounds.minX) / Math.max(1, bounds.maxY - bounds.minY);
  const w = Math.sqrt(targetArea * aspect);
  const h = targetArea / w;

  const corners = [
    { x: bounds.maxX - w / 2, y: bounds.maxY - h / 2 },
    { x: bounds.minX + w / 2, y: bounds.maxY - h / 2 },
    { x: bounds.maxX - w / 2, y: bounds.minY + h / 2 },
    { x: bounds.minX + w / 2, y: bounds.minY + h / 2 },
  ];

  for (const c of corners) {
    const aabb = { minX: c.x - w / 2, minY: c.y - h / 2, maxX: c.x + w / 2, maxY: c.y + h / 2 };
    const overlaps = objects.some((o) => aabbOverlap(aabb, transformAabb(o.transform), 1));
    if (!overlaps && aabb.minX >= bounds.minX && aabb.maxX <= bounds.maxX && aabb.minY >= bounds.minY && aabb.maxY <= bounds.maxY) {
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
  return [];
}
