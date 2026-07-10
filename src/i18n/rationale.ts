import { t, type Locale } from './translations';
import { objectLabel } from './labels';

// placement.ts stores rationale as a list of small tokens (e.g. 'sunClear',
// 'apartFrom:septic') on each object's metadata instead of a baked English
// sentence, so switching languages retranslates existing layouts instantly.
export function translateRationale(locale: Locale, typeId: string, tokens: string[] | undefined): string {
  const subject = objectLabel(locale, typeId);
  const unique = tokens ? [...new Set(tokens)].slice(0, 2) : [];
  if (unique.length === 0) return t(locale, 'rationale.fallback', { subject });

  const reasons = unique.map((token) => {
    const [kind, arg] = token.split(':');
    switch (kind) {
      case 'accessClose':
        return t(locale, 'rationale.accessClose');
      case 'roadFacing':
        return t(locale, 'rationale.roadFacing');
      case 'boundaryClear':
        return t(locale, 'rationale.boundaryClear');
      case 'apartFrom':
        return t(locale, 'rationale.apartFrom', { related: objectLabel(locale, arg) });
      case 'near':
        return t(locale, 'rationale.near', { related: objectLabel(locale, arg) });
      case 'sunClear':
        return t(locale, 'rationale.sunClear');
      case 'aligned':
        return t(locale, 'rationale.aligned');
      case 'backYard':
        return t(locale, 'rationale.backYard');
      case 'roofMounted':
        return t(locale, 'rationale.roofMounted');
      default:
        return kind;
    }
  });

  return t(locale, 'rationale.summary', { subject, reasons: reasons.join('; ') });
}
