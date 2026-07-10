import type { Season, ZoneCategory } from './types';

export const SEASONS: Season[] = ['spring', 'summer', 'autumn', 'winter'];

// Base-fill tint override for seasonal mode, applied only to categories
// whose appearance genuinely changes with the season (crops/orchards).
// `summer` intentionally returns undefined everywhere — it's the same
// look as the always-on schematic/design rendering.
const SEASON_FILL: Partial<Record<ZoneCategory, Partial<Record<Season, string>>>> = {
  'food-annual': {
    winter: '#c9bfa8',
    spring: '#d7e4c5',
    autumn: '#d9b45c',
  },
  'food-perennial': {
    winter: '#d8dcd0',
    spring: '#e8f0d8',
    autumn: '#c98f4a',
  },
};

export function seasonalFillOverride(category: ZoneCategory, season: Season | undefined): string | undefined {
  if (!season) return undefined;
  return SEASON_FILL[category]?.[season];
}
