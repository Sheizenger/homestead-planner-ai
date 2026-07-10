import { describe, expect, it } from 'vitest';
import { computeHouseholdAreaWarning, computeClimateCropWarnings, RECOMMENDED_M2_PER_PERSON } from './warnings';

describe('computeHouseholdAreaWarning', () => {
  it('returns null when the plot meets the per-person guideline', () => {
    const warning = computeHouseholdAreaWarning(4 * RECOMMENDED_M2_PER_PERSON, 4);
    expect(warning).toBeNull();
  });

  it('flags a critical shortfall when far below the guideline', () => {
    const warning = computeHouseholdAreaWarning(300, 9);
    expect(warning?.severity).toBe('critical');
  });

  it('flags a caution when moderately below the guideline', () => {
    const recommended = 4 * RECOMMENDED_M2_PER_PERSON;
    const warning = computeHouseholdAreaWarning(recommended * 0.9, 4);
    expect(warning?.severity).toBe('caution');
  });
});

describe('computeClimateCropWarnings', () => {
  it('flags grapevines in a cold climate', () => {
    const warnings = computeClimateCropWarnings('cold', ['vineyard']);
    expect(warnings.some((w) => w.ruleId === 'climate-crop-fit')).toBe(true);
  });

  it('does not flag grapevines in a mediterranean climate', () => {
    const warnings = computeClimateCropWarnings('mediterranean', ['vineyard']);
    expect(warnings).toHaveLength(0);
  });

  it('only checks crops actually present in the brief', () => {
    const warnings = computeClimateCropWarnings('arid', ['potato']);
    expect(warnings.every((w) => w.message.toLowerCase().startsWith('potato'))).toBe(true);
  });
});
