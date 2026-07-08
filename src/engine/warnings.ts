import type { AnalyticsSnapshot, Fence, PlanObject, Warning } from '../domain/types';
import { CONSTRAINTS } from '../domain/constraints';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { distance, transformAabb, aabbOverlap } from './geometry';

function matches(entryId: string, entryCategory: string, list: string[]): boolean {
  return list.includes(entryId) || list.includes(entryCategory);
}

export function computeWarnings(objects: PlanObject[], fences: Fence[], analytics: AnalyticsSnapshot): Warning[] {
  const warnings: Warning[] = [];

  for (const c of CONSTRAINTS) {
    for (const subject of objects) {
      const subjectEntry = OBJECT_LIBRARY[subject.typeId];
      if (!subjectEntry || !matches(subjectEntry.id, subjectEntry.category, c.subjectTypes)) continue;
      for (const related of objects) {
        if (related.id === subject.id) continue;
        const relatedEntry = OBJECT_LIBRARY[related.typeId];
        if (!relatedEntry || !matches(relatedEntry.id, relatedEntry.category, c.relatedTypes)) continue;
        const d = distance(subject.transform, related.transform);
        if (c.kind === 'separation' && c.minDistance && d < c.minDistance) {
          warnings.push({
            id: `warn-${c.id}-${subject.id}-${related.id}`,
            severity: c.severity,
            message: `${subject.label} and ${related.label}: ${c.message}`,
            ruleId: c.id,
            objectIds: [subject.id, related.id],
            suggestedFix: { label: 'Move apart', action: 'increase-separation' },
          });
        }
        if (c.kind === 'adjacency' && c.maxDistance && d > c.maxDistance) {
          warnings.push({
            id: `warn-${c.id}-${subject.id}-${related.id}`,
            severity: c.severity,
            message: `${subject.label} and ${related.label}: ${c.message}`,
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
        ruleId: 'containment-required',
        objectIds: [obj.id],
      });
    }
  }

  for (let i = 0; i < objects.length; i++) {
    for (let j = i + 1; j < objects.length; j++) {
      const a = objects[i];
      const b = objects[j];
      if (aabbOverlap(transformAabb(a.transform), transformAabb(b.transform))) {
        warnings.push({
          id: `warn-overlap-${a.id}-${b.id}`,
          severity: 'critical',
          message: `${a.label} and ${b.label} overlap on the plan.`,
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
      ruleId: 'capacity-overflow',
      objectIds: [],
    });
  } else if (analytics.allocatedAreaM2 > analytics.totalAreaM2 * 0.9) {
    warnings.push({
      id: 'warn-near-capacity',
      severity: 'caution',
      message: 'Plan uses over 90% of the plot, leaving little room for adjustment or future changes.',
      ruleId: 'capacity-near-limit',
      objectIds: [],
    });
  }

  const severityRank: Record<Warning['severity'], number> = { critical: 0, caution: 1, info: 2 };
  return warnings.sort((a, b) => severityRank[a.severity] - severityRank[b.severity]);
}
