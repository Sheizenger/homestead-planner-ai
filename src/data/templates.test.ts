import { describe, expect, it } from 'vitest';
import { PROJECT_TEMPLATES, buildProjectFromTemplate } from './templates';
import { generateVariants } from '../engine/generate';

describe('project templates', () => {
  for (const template of PROJECT_TEMPLATES) {
    it(`"${template.id}" builds a valid project and generates without crashing`, () => {
      const project = buildProjectFromTemplate(template, `Test — ${template.id}`);
      expect(project.plot.boundary).toHaveLength(4);
      const variants = generateVariants(project);
      expect(variants).toHaveLength(3);
      for (const v of variants) {
        expect(v.objects.some((o) => o.typeId === 'house' || o.typeId === 'house-l')).toBe(true);
      }
    });

    it(`"${template.id}" fits its whole program on its own default plot size`, () => {
      // Guards against a template whose infrastructure/crop list is too
      // ambitious for the plot size shipped alongside it — a new user
      // picking a template shouldn't immediately see "could not fit" errors.
      const project = buildProjectFromTemplate(template, `Test — ${template.id}`);
      const [variant] = generateVariants(project);
      const unplaced = variant.warnings.filter((w) => w.ruleId === 'capacity-overflow');
      expect(unplaced).toEqual([]);
    });
  }
});
