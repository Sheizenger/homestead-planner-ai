import type { AnalyticsSnapshot, ClimateZone, Fence, PlanObject, Plot, Warning } from '../domain/types';
import { CONSTRAINTS, BOUNDARY_SETBACKS } from '../domain/constraints';
import { CROP_CLIMATE_NOTES } from '../domain/climateData';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { distance, distanceToPolygonBoundary, transformAabb, aabbOverlap } from './geometry';
import { isHydroFeasible } from './waterfront';

export function computeHydroFeasibilityWarnings(plot: Plot, objects: PlanObject[]): Warning[] {
  const turbine = objects.find((o) => o.typeId === 'micro-hydro');
  if (!turbine || isHydroFeasible(plot)) return [];
  return [
    {
      id: 'warn-hydro-infeasible',
      severity: 'caution',
      message:
        "The configured waterfront doesn't have enough flow speed or elevation drop for a micro-hydro turbine to generate meaningful power — consider a stronger site or reconsidering this feature.",
      messageKey: 'warning.hydroInfeasible',
      ruleId: 'hydro-infeasible',
      objectIds: [turbine.id],
    },
  ];
}

function matches(entryId: string, entryCategory: string, list: string[]): boolean {
  return list.includes(entryId) || list.includes(entryCategory);
}

// Rough planning guideline for a self-sufficient homestead (living space +
// garden + some animals) — not a legal minimum, just a sanity check so a
// large household isn't planned onto a plot that can't realistically fit
// its program. Real sanitary-minimum norms (~15 m²/person) are for urban
// housing and don't apply to this kind of plot.
export const RECOMMENDED_M2_PER_PERSON = 250;

export function computeHouseholdAreaWarning(totalAreaM2: number, householdSize: number): Warning | null {
  const recommended = householdSize * RECOMMENDED_M2_PER_PERSON;
  if (totalAreaM2 >= recommended) return null;
  const shortfall = Math.ceil(recommended - totalAreaM2);
  const severity = totalAreaM2 < recommended * 0.6 ? 'critical' : 'caution';
  return {
    id: 'warn-household-area-norm',
    severity,
    message: `For ${householdSize} resident${householdSize === 1 ? '' : 's'}, a self-sufficient homestead typically needs around ${recommended.toLocaleString()} m² (~${RECOMMENDED_M2_PER_PERSON} m²/person); this plot is short by about ${shortfall.toLocaleString()} m². Consider a larger plot or a smaller household program.`,
    messageKey: 'warning.householdArea',
    messageParams: {
      household: householdSize,
      recommended: recommended.toLocaleString(),
      perPerson: RECOMMENDED_M2_PER_PERSON,
      shortfall: shortfall.toLocaleString(),
    },
    ruleId: 'household-area-norm',
    objectIds: [],
  };
}

export function computeClimateCropWarnings(climateZone: ClimateZone, crops: string[]): Warning[] {
  const warnings: Warning[] = [];
  for (const note of CROP_CLIMATE_NOTES) {
    if (!crops.includes(note.crop) || !note.questionableZones.includes(climateZone)) continue;
    warnings.push({
      id: `warn-climate-${note.crop}`,
      severity: note.severity,
      message: `${note.crop[0].toUpperCase()}${note.crop.slice(1)} in a ${climateZone} climate: ${note.message}`,
      messageKey: 'warning.climateCropFit',
      messageParams: { crop: note.crop, zone: climateZone },
      ruleId: 'climate-crop-fit',
      objectIds: [],
    });
  }
  return warnings;
}

export function computeWarnings(
  objects: PlanObject[],
  fences: Fence[],
  analytics: AnalyticsSnapshot,
  plot: Plot,
  householdSize: number,
  climateZone: ClimateZone,
  crops: string[],
): Warning[] {
  const warnings: Warning[] = [];

  const householdWarning = computeHouseholdAreaWarning(analytics.totalAreaM2, householdSize);
  if (householdWarning) warnings.push(householdWarning);
  warnings.push(...computeClimateCropWarnings(climateZone, crops));
  warnings.push(...computeHydroFeasibilityWarnings(plot, objects));

  // subjectTypes/relatedTypes can be the same list (e.g. "any two
  // outbuildings"), which would otherwise match a pair in both directions
  // and report it twice — dedupe on the unordered pair regardless of which
  // side matched "subject" vs "related".
  const reportedPairs = new Set<string>();

  for (const c of CONSTRAINTS) {
    for (const subject of objects) {
      const subjectEntry = OBJECT_LIBRARY[subject.typeId];
      if (!subjectEntry || !matches(subjectEntry.id, subjectEntry.category, c.subjectTypes)) continue;
      for (const related of objects) {
        if (related.id === subject.id) continue;
        const relatedEntry = OBJECT_LIBRARY[related.typeId];
        if (!relatedEntry || !matches(relatedEntry.id, relatedEntry.category, c.relatedTypes)) continue;
        // Roof-mounted equipment isn't a ground-level obstacle — skip
        // ground clearance/separation checks (adjacency, e.g. cable-run
        // distance, still applies).
        if ((c.kind === 'separation' || c.kind === 'safety') && (subject.metadata.roofMounted || related.metadata.roofMounted)) continue;
        const pairKey = `${c.id}:${[subject.id, related.id].sort().join('|')}`;
        if (reportedPairs.has(pairKey)) continue;
        const d = distance(subject.transform, related.transform);
        if ((c.kind === 'separation' || c.kind === 'safety') && c.minDistance && d < c.minDistance) {
          reportedPairs.add(pairKey);
          warnings.push({
            id: `warn-${c.id}-${subject.id}-${related.id}`,
            severity: c.severity,
            message: `${subject.label} and ${related.label}: ${c.message}`,
            messageKey: 'warning.pair',
            messageParams: { ruleId: c.id, subjectType: subject.typeId, relatedType: related.typeId },
            ruleId: c.id,
            objectIds: [subject.id, related.id],
            suggestedFix: { label: 'Move apart', action: 'increase-separation' },
          });
        }
        if (c.kind === 'adjacency' && c.maxDistance && d > c.maxDistance) {
          reportedPairs.add(pairKey);
          warnings.push({
            id: `warn-${c.id}-${subject.id}-${related.id}`,
            severity: c.severity,
            message: `${subject.label} and ${related.label}: ${c.message}`,
            messageKey: 'warning.pair',
            messageParams: { ruleId: c.id, subjectType: subject.typeId, relatedType: related.typeId },
            ruleId: c.id,
            objectIds: [subject.id, related.id],
            suggestedFix: { label: 'Move closer', action: 'decrease-separation' },
          });
        }
      }
    }
  }

  for (const obj of objects) {
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry?.requiresFence) continue;
    const hasFence = fences.some((f) => f.id === `fence-${obj.id}`);
    if (!hasFence) {
      warnings.push({
        id: `warn-unfenced-${obj.id}`,
        severity: 'caution',
        message: `${obj.label} normally requires containment fencing but none is present.`,
        messageKey: 'warning.containmentRequired',
        messageParams: { subjectType: obj.typeId },
        ruleId: 'containment-required',
        objectIds: [obj.id],
      });
    }
  }

  for (const obj of objects) {
    const entry = OBJECT_LIBRARY[obj.typeId];
    if (!entry) continue;
    for (const setback of BOUNDARY_SETBACKS) {
      if (!(setback.appliesTo.includes(entry.id) || setback.appliesTo.includes(entry.category))) continue;
      const d = distanceToPolygonBoundary(obj.transform, plot.boundary);
      if (d < setback.minDistanceM) {
        warnings.push({
          id: `warn-${setback.id}-${obj.id}`,
          severity: setback.severity,
          message: `${obj.label} ${setback.message}`,
          messageKey: 'warning.single',
          messageParams: { ruleId: setback.id, subjectType: obj.typeId },
          ruleId: setback.id,
          objectIds: [obj.id],
          suggestedFix: { label: 'Move away from boundary', action: 'increase-separation' },
        });
      }
    }
  }

  for (let i = 0; i < objects.length; i++) {
    for (let j = i + 1; j < objects.length; j++) {
      const a = objects[i];
      const b = objects[j];
      if (a.metadata.roofMounted || b.metadata.roofMounted) continue; // meant to overlap the house footprint
      if (aabbOverlap(transformAabb(a.transform), transformAabb(b.transform))) {
        warnings.push({
          id: `warn-overlap-${a.id}-${b.id}`,
          severity: 'critical',
          message: `${a.label} and ${b.label} overlap on the plan.`,
          messageKey: 'warning.overlap',
          messageParams: { subjectType: a.typeId, relatedType: b.typeId },
          ruleId: 'object-overlap',
          objectIds: [a.id, b.id],
          suggestedFix: { label: 'Move apart', action: 'increase-separation' },
        });
      }
    }
  }

  if (analytics.allocatedAreaM2 > analytics.totalAreaM2) {
    const overPercent = Math.round(((analytics.allocatedAreaM2 - analytics.totalAreaM2) / analytics.totalAreaM2) * 100);
    warnings.push({
      id: 'warn-overallocated',
      severity: 'critical',
      message: `Plan exceeds the available plot area by ${overPercent}%. Reduce zone sizes or the plot's program.`,
      messageKey: 'warning.overallocated',
      messageParams: { percent: overPercent },
      ruleId: 'capacity-overflow',
      objectIds: [],
    });
  } else if (analytics.allocatedAreaM2 > analytics.totalAreaM2 * 0.9) {
    warnings.push({
      id: 'warn-near-capacity',
      severity: 'caution',
      message: 'Plan uses over 90% of the plot, leaving little room for adjustment or future changes.',
      messageKey: 'warning.nearCapacity',
      ruleId: 'capacity-near-limit',
      objectIds: [],
    });
  }

  const severityRank: Record<Warning['severity'], number> = { critical: 0, caution: 1, info: 2 };
  return warnings.sort((a, b) => severityRank[a.severity] - severityRank[b.severity]);
}
