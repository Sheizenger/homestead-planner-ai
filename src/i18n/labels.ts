import type { ClimateZone, PlanningMode, Season, ZoneCategory } from '../domain/types';
import { t, type Locale } from './translations';

// Anything keyed by a stable id (object type, category, season, planning
// mode, climate zone) is translated by id at render time rather than by
// reading a stored English label — so switching languages updates every
// occurrence instantly, including on already-generated layouts.
export function objectLabel(locale: Locale, typeId: string): string {
  return t(locale, `object.${typeId}`);
}

export function categoryLabel(locale: Locale, category: ZoneCategory): string {
  return t(locale, `category.${category}`);
}

export function seasonLabel(locale: Locale, season: Season): string {
  return t(locale, `season.${season}`);
}

export function planningModeLabel(locale: Locale, mode: PlanningMode): string {
  return t(locale, `planningMode.${mode}`);
}

export function climateZoneLabel(locale: Locale, zone: ClimateZone): string {
  return t(locale, `climateZone.${zone}`);
}
