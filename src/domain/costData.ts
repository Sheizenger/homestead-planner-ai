import type { ObjectCategory } from './types';

export type CurrencyCode = 'USD' | 'EUR' | 'RUB';

export const CURRENCIES: CurrencyCode[] = ['USD', 'EUR', 'RUB'];

export const CURRENCY_SYMBOLS: Record<CurrencyCode, string> = {
  USD: '$',
  EUR: '€',
  RUB: '₽',
};

// Static, approximate — not a live feed. Good enough for order-of-magnitude
// planning; refresh periodically if used for anything more serious.
export const USD_EXCHANGE_RATES: Record<CurrencyCode, number> = {
  USD: 1,
  EUR: 0.92,
  RUB: 82,
};

export function convertFromUsd(amountUsd: number, currency: CurrencyCode): number {
  return amountUsd * USD_EXCHANGE_RATES[currency];
}

export interface CostRegion {
  id: string;
  country: string;
  region?: string; // state / federal subject / etc.
  landPricePerM2Usd: number;
  laborIndex: number; // construction/installation cost multiplier, US-national = 1.0
  maintenanceIndex: number; // ongoing upkeep cost multiplier
}

// Land prices and labor indices are rough 2025-market-report approximations
// converted to a common USD/m² baseline for comparison — not appraisals.
// Real prices vary widely by exact parcel, access, and utilities. Use
// "Custom / other location" to override with local knowledge.
export const COST_REGIONS: CostRegion[] = [
  { id: 'custom', country: 'Custom / other location', landPricePerM2Usd: 5, laborIndex: 1, maintenanceIndex: 1 },

  { id: 'us-national', country: 'United States', region: 'National average', landPricePerM2Usd: 3, laborIndex: 1.0, maintenanceIndex: 1.0 },
  { id: 'us-california', country: 'United States', region: 'California', landPricePerM2Usd: 35, laborIndex: 1.3, maintenanceIndex: 1.2 },
  { id: 'us-texas', country: 'United States', region: 'Texas', landPricePerM2Usd: 2.5, laborIndex: 0.85, maintenanceIndex: 0.9 },

  { id: 'de-national', country: 'Germany', region: 'National average', landPricePerM2Usd: 239, laborIndex: 1.2, maintenanceIndex: 1.1 },
  { id: 'de-bavaria', country: 'Germany', region: 'Bavaria', landPricePerM2Usd: 429, laborIndex: 1.35, maintenanceIndex: 1.2 },
  { id: 'de-saxony-anhalt', country: 'Germany', region: 'Saxony-Anhalt', landPricePerM2Usd: 87, laborIndex: 0.95, maintenanceIndex: 0.9 },

  { id: 'ru-national', country: 'Russia', region: 'Rural average', landPricePerM2Usd: 1.8, laborIndex: 0.4, maintenanceIndex: 0.4 },
  { id: 'ru-moscow-region', country: 'Russia', region: 'Moscow Region', landPricePerM2Usd: 49, laborIndex: 0.5, maintenanceIndex: 0.45 },

  { id: 'ua-national', country: 'Ukraine', region: 'National average', landPricePerM2Usd: 0.6, laborIndex: 0.25, maintenanceIndex: 0.3 },
  { id: 'kz-national', country: 'Kazakhstan', region: 'National average', landPricePerM2Usd: 0.5, laborIndex: 0.3, maintenanceIndex: 0.3 },
  { id: 'uk-national', country: 'United Kingdom', region: 'National average', landPricePerM2Usd: 20, laborIndex: 1.3, maintenanceIndex: 1.2 },
  { id: 'fr-national', country: 'France', region: 'National average', landPricePerM2Usd: 15, laborIndex: 1.15, maintenanceIndex: 1.1 },
  { id: 'es-national', country: 'Spain', region: 'National average', landPricePerM2Usd: 8, laborIndex: 0.9, maintenanceIndex: 0.9 },
  { id: 'ca-national', country: 'Canada', region: 'National average', landPricePerM2Usd: 6, laborIndex: 1.1, maintenanceIndex: 1.05 },
  { id: 'pl-national', country: 'Poland', region: 'National average', landPricePerM2Usd: 4, laborIndex: 0.55, maintenanceIndex: 0.5 },
];

export interface ObjectCostEntry {
  installPerM2?: number; // USD, US-national labor baseline
  installFixed?: number;
  annualPerM2?: number;
  annualFixed?: number;
  annualPerAnimal?: number; // uses metadata.animalCount when present
}

// US-national baseline (laborIndex 1.0) construction/installation and annual
// upkeep costs in USD, per object-library type id. Scaled per-region by
// laborIndex/maintenanceIndex in engine/costs.ts. Rough planning figures, not
// contractor quotes — materials, permits, and site conditions all move these.
export const OBJECT_COST_TABLE: Record<string, ObjectCostEntry> = {
  house: { installPerM2: 2000, annualPerM2: 15 },
  'house-l': { installPerM2: 2050, annualPerM2: 15 },
  garage: { installPerM2: 500, annualPerM2: 8 },
  shed: { installPerM2: 250, annualPerM2: 4 },
  barn: { installPerM2: 350, annualPerM2: 6 },
  cellar: { installPerM2: 400, annualPerM2: 3 },
  woodshed: { installPerM2: 200, annualPerM2: 3 },
  patio: { installPerM2: 120, annualPerM2: 2 },
  greenhouse: { installPerM2: 180, annualPerM2: 12 },
  'hydroponic-tower': { installPerM2: 350, annualPerM2: 40 },
  'raised-beds': { installPerM2: 60, annualPerM2: 8 },
  'vegetable-area': { installPerM2: 8, annualPerM2: 6 },
  'potato-area': { installPerM2: 5, annualPerM2: 4 },
  'grain-field': { installPerM2: 4, annualPerM2: 3 },
  'orchard-trees': { installPerM2: 12, annualPerM2: 3 },
  'berry-rows': { installPerM2: 15, annualPerM2: 5 },
  vineyard: { installPerM2: 20, annualPerM2: 6 },
  'goat-shelter': { installPerM2: 300, annualPerM2: 5 },
  'goat-paddock': { installPerM2: 6, annualPerM2: 2, annualPerAnimal: 250 },
  'poultry-coop': { installPerM2: 250, annualPerM2: 5, annualPerAnimal: 25 },
  compost: { installFixed: 150, annualFixed: 20 },
  'water-tank': { installFixed: 1500, annualFixed: 40 },
  well: { installFixed: 4500, annualFixed: 100 },
  pump: { installFixed: 900, annualFixed: 60 },
  septic: { installFixed: 6000, annualFixed: 150 },
  'solar-array': { installPerM2: 280, annualFixed: 100 },
  'battery-room': { installFixed: 5000, annualFixed: 80 },
  'inverter-room': { installFixed: 1800, annualFixed: 40 },
  generator: { installFixed: 1200, annualFixed: 150 },
  pool: { installPerM2: 900, annualFixed: 600, annualPerM2: 15 },
  gazebo: { installPerM2: 250, annualPerM2: 3 },
  apiary: { installFixed: 800, annualFixed: 150 },
  banya: { installPerM2: 900, annualPerM2: 8 },
  smokehouse: { installFixed: 600, annualFixed: 20 },
  workshop: { installPerM2: 350, annualPerM2: 6 },
  'rainwater-cistern': { installFixed: 1000, annualFixed: 30 },
};

export const PATH_COST_PER_M2: Record<string, { install: number; annual: number }> = {
  paved: { install: 45, annual: 1 },
  gravel: { install: 10, annual: 0.3 },
  mulch: { install: 6, annual: 0.5 },
  grass: { install: 3, annual: 0.4 },
};

export const FENCE_COST_PER_M: Record<string, { install: number; annual: number }> = {
  perimeter: { install: 18, annual: 0.5 },
  paddock: { install: 12, annual: 0.3 },
  garden: { install: 9, annual: 0.2 },
  decorative: { install: 14, annual: 0.3 },
};

export function regionLabel(region: CostRegion): string {
  return region.region && region.region !== 'National average' ? `${region.country} — ${region.region}` : region.country;
}

export const OBJECT_CATEGORY_FALLBACK_COST: Partial<Record<ObjectCategory, ObjectCostEntry>> = {
  storage: { installPerM2: 280, annualPerM2: 5 },
  leisure: { installPerM2: 150, annualPerM2: 4 },
  energy: { installFixed: 1500, annualFixed: 60 },
  water: { installFixed: 1200, annualFixed: 50 },
  utility: { installFixed: 800, annualFixed: 40 },
  animal: { installPerM2: 100, annualFixed: 100 },
};
