import type { ClimateZone, Warning } from '../domain/types';
import { t, type Locale } from './translations';
import { objectLabel, climateZoneLabel } from './labels';

// Warnings are generated once by the engine (constraints.ts/warnings.ts) and
// stored with a messageKey + structured params instead of a baked English
// sentence, so switching the UI language retranslates every existing
// warning instantly — no need to regenerate the layout.
export function translateWarning(locale: Locale, w: Warning): string {
  const key = w.messageKey;
  const p = w.messageParams ?? {};
  if (!key) return w.message;

  switch (key) {
    case 'warning.pair': {
      const subject = objectLabel(locale, String(p.subjectType));
      const related = objectLabel(locale, String(p.relatedType));
      const connector = t(locale, 'warning.connector.pair', { subject, related });
      return connector + t(locale, `warning.rule.${p.ruleId}`);
    }
    case 'warning.single': {
      const subject = objectLabel(locale, String(p.subjectType));
      return `${subject} ${t(locale, `warning.rule.${p.ruleId}`)}`;
    }
    case 'warning.overlap': {
      const subject = objectLabel(locale, String(p.subjectType));
      const related = objectLabel(locale, String(p.relatedType));
      return t(locale, 'warning.overlap', { subject, related });
    }
    case 'warning.containmentRequired': {
      const subject = objectLabel(locale, String(p.subjectType));
      return t(locale, 'warning.containmentRequired', { subject });
    }
    case 'warning.unplaced': {
      const item = objectLabel(locale, String(p.itemType));
      return t(locale, 'warning.unplaced', { item });
    }
    case 'warning.climateCropFit': {
      const crop = t(locale, `crop.${p.crop}`);
      const zone = climateZoneLabel(locale, p.zone as ClimateZone).toLowerCase();
      const note = t(locale, `climateNote.${p.crop}`);
      const rendered = t(locale, 'warning.climateCropFit', { crop, zone, note });
      return rendered.charAt(0).toUpperCase() + rendered.slice(1);
    }
    default:
      return t(locale, key, p);
  }
}
