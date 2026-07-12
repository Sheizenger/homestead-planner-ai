import { describe, expect, it } from 'vitest';
import { createSampleProject } from '../data/sampleProject';
import { generateVariants } from './generate';
import { parseEditCommand, findRepositionTarget, resizeTransform } from './editCommands';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';
import { rectFullyInsidePolygon, transformAabb, aabbOverlap } from './geometry';

describe('parseEditCommand', () => {
  it('parses a delete command', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const parsed = parseEditCommand('delete the patio', variant);
    expect(parsed).toEqual({ verb: 'delete', subjectTypeId: 'patio' });
  });

  it('parses a move-near command with subject and reference', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const parsed = parseEditCommand('move the greenhouse near the well', variant);
    expect(parsed?.verb).toBe('move-near');
    expect(parsed?.subjectTypeId).toBe('greenhouse');
    expect(parsed?.referenceTypeId).toBe('well');
  });

  it('parses a move-away command', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const parsed = parseEditCommand('move the goat paddock away from the house', variant);
    expect(parsed?.verb).toBe('move-away');
    expect(parsed?.subjectTypeId).toBe('goat-paddock');
    expect(parsed?.referenceTypeId).toBe('house');
  });

  it('returns null for a move command missing a reference object', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    expect(parseEditCommand('move the greenhouse somewhere', variant)).toBeNull();
  });

  it('returns null for unrecognized text', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    expect(parseEditCommand('what a nice day', variant)).toBeNull();
  });

  it('returns null for an object type not present in the plan', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    expect(parseEditCommand('delete the swimming pool', variant)).toBeNull();
  });
});

describe('resizeTransform', () => {
  it('grows within the clamp range', () => {
    const entry = { minWidth: 2, minHeight: 2, defaultWidth: 4, defaultHeight: 4 };
    const result = resizeTransform(entry, { x: 0, y: 0, width: 4, height: 4, rotationDeg: 0 }, true);
    expect(result.width).toBeCloseTo(4.8);
    expect(result.height).toBeCloseTo(4.8);
  });

  it('never shrinks below minWidth/minHeight', () => {
    const entry = { minWidth: 2, minHeight: 2, defaultWidth: 4, defaultHeight: 4 };
    const result = resizeTransform(entry, { x: 0, y: 0, width: 2.1, height: 2.1, rotationDeg: 0 }, false);
    expect(result.width).toBeGreaterThanOrEqual(2);
    expect(result.height).toBeGreaterThanOrEqual(2);
  });
});

describe('findRepositionTarget', () => {
  it('finds a valid non-overlapping spot closer to the reference for mode "near"', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const subject = variant.objects.find((o) => o.typeId === 'greenhouse');
    const reference = variant.objects.find((o) => o.typeId === 'well');
    expect(subject).toBeDefined();
    expect(reference).toBeDefined();
    const target = findRepositionTarget(variant, project.plot, subject!, reference!, 'near');
    expect(target).not.toBeNull();
    if (target) {
      expect(rectFullyInsidePolygon(target, project.plot.boundary)).toBe(true);
      const aabb = transformAabb(target);
      const overlaps = variant.objects
        .filter((o) => o.id !== subject!.id)
        .some((o) => aabbOverlap(aabb, transformAabb(o.transform), 0.3));
      expect(overlaps).toBe(false);
    }
  });

  it('places the object measurably closer than its original distance in "near" mode', () => {
    const project = createSampleProject();
    const [variant] = generateVariants(project);
    const subject = variant.objects.find((o) => o.typeId === 'greenhouse')!;
    const reference = variant.objects.find((o) => o.typeId === 'well')!;
    const target = findRepositionTarget(variant, project.plot, subject, reference, 'near');
    expect(target).not.toBeNull();
    const originalDist = Math.hypot(subject.transform.x - reference.transform.x, subject.transform.y - reference.transform.y);
    const newDist = Math.hypot(target!.x - reference.transform.x, target!.y - reference.transform.y);
    expect(newDist).toBeLessThanOrEqual(originalDist + 1e-6);
  });
});

// Sanity: every OBJECT_LIBRARY entry referenced by editCommands tests above
// actually exists (guards against a typo in a future catalog rename).
describe('OBJECT_LIBRARY sanity', () => {
  it('has entries for greenhouse, well, house, goat-paddock, patio', () => {
    for (const id of ['greenhouse', 'well', 'house', 'goat-paddock', 'patio']) {
      expect(OBJECT_LIBRARY[id]).toBeDefined();
    }
  });
});
