import type { ZoneCategory } from './types';

export interface CategoryStyle {
  label: string;
  light: { fill: string; stroke: string };
  dark: { fill: string; stroke: string };
}

// Muted, distinguishable architectural-plan palette (not gradient/toy-styled).
export const CATEGORY_STYLES: Record<ZoneCategory, CategoryStyle> = {
  residential: {
    label: 'Residential',
    light: { fill: '#e4dccb', stroke: '#8a7a58' },
    dark: { fill: '#3a3527', stroke: '#c8b88a' },
  },
  access: {
    label: 'Access & Paths',
    light: { fill: '#d9d4c9', stroke: '#8a8474' },
    dark: { fill: '#33312b', stroke: '#a9a48f' },
  },
  'food-annual': {
    label: 'Annual Crops',
    light: { fill: '#d7e4c5', stroke: '#5f7d3a' },
    dark: { fill: '#2b331f', stroke: '#9dbf78' },
  },
  'food-perennial': {
    label: 'Orchard & Berries',
    light: { fill: '#c9dfc4', stroke: '#3f6b3a' },
    dark: { fill: '#213328', stroke: '#7fae76' },
  },
  greenhouse: {
    label: 'Greenhouse',
    light: { fill: '#cfe6e6', stroke: '#3f7d7d' },
    dark: { fill: '#1f3333', stroke: '#7fbdbd' },
  },
  animal: {
    label: 'Animals',
    light: { fill: '#e8d9c3', stroke: '#8a5f2f' },
    dark: { fill: '#332a1c', stroke: '#c9a06b' },
  },
  utility: {
    label: 'Utilities',
    light: { fill: '#dcdcdc', stroke: '#6b6b6b' },
    dark: { fill: '#2e2e2e', stroke: '#a3a3a3' },
  },
  water: {
    label: 'Water',
    light: { fill: '#c3d9e8', stroke: '#2f5f8a' },
    dark: { fill: '#1c2a33', stroke: '#6ba3c9' },
  },
  energy: {
    label: 'Energy',
    light: { fill: '#e8e0c3', stroke: '#8a7a2f' },
    dark: { fill: '#332f1c', stroke: '#c9b96b' },
  },
  storage: {
    label: 'Storage',
    light: { fill: '#ddd2c3', stroke: '#7d5f3f' },
    dark: { fill: '#2f271e', stroke: '#bfa076' },
  },
  leisure: {
    label: 'Leisure',
    light: { fill: '#e0d3e6', stroke: '#6b4a7d' },
    dark: { fill: '#2b2233', stroke: '#a97fc9' },
  },
  'future-expansion': {
    label: 'Future Expansion',
    light: { fill: '#f0f0f0', stroke: '#999999' },
    dark: { fill: '#262626', stroke: '#777777' },
  },
};

// A few object types read strongly as a specific material regardless of
// their placement category — a pool is 'leisure' for siting/warning
// purposes but should still look like water, not generic leisure-purple.
export const TYPE_STYLE_OVERRIDE: Record<string, { light: { fill: string; stroke: string }; dark: { fill: string; stroke: string } }> = {
  pool: {
    light: { fill: '#bfe6f0', stroke: '#1a7fa3' },
    dark: { fill: '#153a42', stroke: '#5fc3dd' },
  },
};

export const ZONE_CATEGORY_ORDER: ZoneCategory[] = [
  'residential',
  'access',
  'food-annual',
  'food-perennial',
  'greenhouse',
  'animal',
  'utility',
  'water',
  'energy',
  'storage',
  'leisure',
  'future-expansion',
];
