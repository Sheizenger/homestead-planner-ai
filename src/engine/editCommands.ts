import type { LayoutVariant, PlanObject, Plot, Transform } from '../domain/types';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { polygonBounds, rectFullyInsidePolygon, transformAabb, aabbOverlap, distance } from './geometry';

// Bounded-vocabulary editing commands, in the same spirit as textParser.ts's
// brief extraction: free text is matched against a fixed set of verbs and the
// object type labels actually present in the current plan, rather than sent
// to an open-ended model, so results stay deterministic and explainable.

export type EditVerb = 'move-near' | 'move-away' | 'enlarge' | 'shrink' | 'delete' | 'duplicate' | 'rotate' | 'lock' | 'unlock';

export interface ParsedEditCommand {
  verb: EditVerb;
  subjectTypeId: string;
  referenceTypeId?: string;
}

// Order matters: more specific phrases (e.g. "away from") must be tested
// before their broader counterparts wouldn't otherwise conflict, but this
// also fixes priority when a command could ambiguously match more than one
// verb family (delete/duplicate/rotate/lock take priority over resize or
// move phrasing that might incidentally share a word).
const VERB_PATTERNS: { verb: EditVerb; re: RegExp }[] = [
  { verb: 'delete', re: /\b(delete|remove)\b/ },
  { verb: 'duplicate', re: /\b(duplicate|copy|clone)\b/ },
  { verb: 'rotate', re: /\b(rotate|turn)\b/ },
  { verb: 'unlock', re: /\bunlock\b/ },
  { verb: 'lock', re: /\block\b/ },
  { verb: 'enlarge', re: /\b(bigger|larger|enlarge|increase|grow|expand)\b/ },
  { verb: 'shrink', re: /\b(smaller|shrink|decrease|reduce|shrink)\b/ },
  { verb: 'move-away', re: /\b(away from|farther from|further from|far from)\b/ },
  { verb: 'move-near', re: /\b(near|closer to|next to|beside|by the)\b/ },
];

function findVerb(text: string): EditVerb | null {
  for (const { verb, re } of VERB_PATTERNS) {
    if (re.test(text)) return verb;
  }
  return null;
}

// Longest-label-first so a multi-word label (e.g. "Solar Panels") wins over
// any shorter label another entry might share a substring with, and each
// matched span is consumed so the same text isn't double-counted.
function findObjectMentions(text: string, candidates: { typeId: string; label: string }[]): { typeId: string; index: number }[] {
  const sorted = [...candidates].sort((a, b) => b.label.length - a.label.length);
  const found: { typeId: string; index: number }[] = [];
  const consumed: [number, number][] = [];
  for (const c of sorted) {
    const idx = text.indexOf(c.label);
    if (idx === -1) continue;
    const overlaps = consumed.some(([s, e]) => idx < e && idx + c.label.length > s);
    if (overlaps) continue;
    found.push({ typeId: c.typeId, index: idx });
    consumed.push([idx, idx + c.label.length]);
  }
  return found.sort((a, b) => a.index - b.index);
}

export function parseEditCommand(text: string, variant: LayoutVariant): ParsedEditCommand | null {
  const lower = text.toLowerCase().trim();
  if (!lower) return null;
  const verb = findVerb(lower);
  if (!verb) return null;

  const presentTypeIds = [...new Set(variant.objects.map((o) => o.typeId))];
  const candidates = presentTypeIds
    .map((typeId) => ({ typeId, label: (OBJECT_LIBRARY[typeId]?.label ?? typeId).toLowerCase() }))
    .filter((c) => c.label.length > 0);

  const mentions = findObjectMentions(lower, candidates);
  if (mentions.length === 0) return null;

  const subjectTypeId = mentions[0].typeId;
  const referenceTypeId = mentions.length > 1 ? mentions[1].typeId : undefined;
  if ((verb === 'move-near' || verb === 'move-away') && !referenceTypeId) return null;

  return { verb, subjectTypeId, referenceTypeId };
}

function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}

export function resizeTransform(entry: { minWidth: number; minHeight: number; defaultWidth: number; defaultHeight: number }, current: Transform, grow: boolean): { width: number; height: number } {
  const factor = grow ? 1.2 : 0.8;
  return {
    width: clamp(current.width * factor, entry.minWidth, entry.defaultWidth * 2.5),
    height: clamp(current.height * factor, entry.minHeight, entry.defaultHeight * 2.5),
  };
}

// Scans the plot for the best non-overlapping spot for `subject` (keeping
// its own size/rotation) that's as close to (mode 'near') or as far from
// (mode 'away') `reference' as the plot allows — the same coarse grid-scan
// approach placement.ts uses, but single-purpose: no sun/adjacency/setback
// scoring, since a manual quick-edit move is meant to behave like dragging
// the object by hand, not like re-running full generation.
export function findRepositionTarget(variant: LayoutVariant, plot: Plot, subject: PlanObject, reference: PlanObject, mode: 'near' | 'away'): Transform | null {
  const bounds = polygonBounds(plot.boundary);
  const w = subject.transform.width;
  const h = subject.transform.height;
  const step = Math.max(0.5, Math.min(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY) / 40);
  const others = variant.objects.filter((o) => o.id !== subject.id);

  let best: { transform: Transform; score: number } | null = null;
  for (let x = bounds.minX + w / 2; x <= bounds.maxX - w / 2; x += step) {
    for (let y = bounds.minY + h / 2; y <= bounds.maxY - h / 2; y += step) {
      const transform: Transform = { x, y, width: w, height: h, rotationDeg: subject.transform.rotationDeg };
      if (!rectFullyInsidePolygon(transform, plot.boundary)) continue;
      const aabb = transformAabb(transform);
      if (others.some((o) => aabbOverlap(aabb, transformAabb(o.transform), 0.3))) continue;
      const d = distance(transform, reference.transform);
      const score = mode === 'near' ? -d : d;
      if (!best || score > best.score) best = { transform, score };
    }
  }
  return best?.transform ?? null;
}
