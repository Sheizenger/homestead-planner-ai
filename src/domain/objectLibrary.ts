import type { ObjectCategory } from './types';

export type PlacementShape = 'rect' | 'circle' | 'oval' | 'lshape';

export interface ObjectLibraryEntry {
  id: string;
  label: string;
  category: ObjectCategory;
  shape: PlacementShape;
  defaultWidth: number; // meters
  defaultHeight: number; // meters
  minWidth: number;
  minHeight: number;
  sunNeed: 'full' | 'partial' | 'none';
  noiseLevel: 'quiet' | 'moderate' | 'loud';
  odorLevel: 'none' | 'mild' | 'strong';
  needsAccess: boolean; // frequently visited -> favor proximity to house
  requiresFence: boolean;
  description: string;
}

export const OBJECT_LIBRARY: Record<string, ObjectLibraryEntry> = {
  house: {
    id: 'house', label: 'House', category: 'residential', shape: 'rect',
    defaultWidth: 12, defaultHeight: 10, minWidth: 6, minHeight: 6,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Primary residence, anchors the plan.',
  },
  'house-l': {
    id: 'house-l', label: 'House', category: 'residential', shape: 'lshape',
    defaultWidth: 14, defaultHeight: 11, minWidth: 7, minHeight: 6,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'L-shaped residence enclosing a private courtyard corner.',
  },
  gazebo: {
    id: 'gazebo', label: 'Gazebo', category: 'leisure', shape: 'circle',
    defaultWidth: 4, defaultHeight: 4, minWidth: 2.5, minHeight: 2.5,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Open-sided shelter for outdoor seating.',
  },
  pool: {
    id: 'pool', label: 'Pool', category: 'leisure', shape: 'oval',
    defaultWidth: 9, defaultHeight: 4.5, minWidth: 4, minHeight: 2.5,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: true, description: 'Swimming pool; full sun and fenced for child safety.',
  },
  garage: {
    id: 'garage', label: 'Garage', category: 'residential', shape: 'rect',
    defaultWidth: 6, defaultHeight: 6, minWidth: 3.5, minHeight: 5,
    sunNeed: 'none', noiseLevel: 'moderate', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Vehicle storage, sited near the road/entry.',
  },
  shed: {
    id: 'shed', label: 'Tool Shed', category: 'storage', shape: 'rect',
    defaultWidth: 4, defaultHeight: 3, minWidth: 2, minHeight: 2,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'General tool and equipment storage.',
  },
  barn: {
    id: 'barn', label: 'Barn', category: 'storage', shape: 'rect',
    defaultWidth: 10, defaultHeight: 8, minWidth: 6, minHeight: 5,
    sunNeed: 'none', noiseLevel: 'moderate', odorLevel: 'mild', needsAccess: true,
    requiresFence: false, description: 'Feed, equipment, and livestock support building.',
  },
  cellar: {
    id: 'cellar', label: 'Root Cellar', category: 'storage', shape: 'rect',
    defaultWidth: 4, defaultHeight: 4, minWidth: 2.5, minHeight: 2.5,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Cool storage for harvested root crops.',
  },
  woodshed: {
    id: 'woodshed', label: 'Woodshed', category: 'storage', shape: 'rect',
    defaultWidth: 4, defaultHeight: 3, minWidth: 2, minHeight: 2,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Dry firewood storage, ideally sun/wind exposed.',
  },
  patio: {
    id: 'patio', label: 'Patio', category: 'leisure', shape: 'rect',
    defaultWidth: 6, defaultHeight: 5, minWidth: 3, minHeight: 3,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Outdoor leisure space adjoining the house.',
  },
  greenhouse: {
    id: 'greenhouse', label: 'Greenhouse', category: 'greenhouse', shape: 'rect',
    defaultWidth: 8, defaultHeight: 5, minWidth: 3, minHeight: 3,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Season-extension growing structure, needs full sun and utility access.',
  },
  'hydroponic-tower': {
    id: 'hydroponic-tower', label: 'Vertical Hydroponic Towers', category: 'greenhouse', shape: 'rect',
    defaultWidth: 3, defaultHeight: 2, minWidth: 1, minHeight: 1,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Space-efficient intensive vertical growing, usually inside/near greenhouse.',
  },
  'raised-beds': {
    id: 'raised-beds', label: 'Raised Beds', category: 'food-annual', shape: 'rect',
    defaultWidth: 8, defaultHeight: 6, minWidth: 2, minHeight: 2,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Kitchen-garden style intensive vegetable beds close to the house.',
  },
  'vegetable-area': {
    id: 'vegetable-area', label: 'Vegetable Area', category: 'food-annual', shape: 'rect',
    defaultWidth: 12, defaultHeight: 10, minWidth: 4, minHeight: 4,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Larger annual vegetable production area.',
  },
  'potato-area': {
    id: 'potato-area', label: 'Potato Field', category: 'food-annual', shape: 'rect',
    defaultWidth: 15, defaultHeight: 10, minWidth: 5, minHeight: 5,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Staple-crop field, tolerant of distance from the house.',
  },
  'grain-field': {
    id: 'grain-field', label: 'Grain Field', category: 'food-annual', shape: 'rect',
    defaultWidth: 20, defaultHeight: 15, minWidth: 8, minHeight: 8,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Extensive staple grain planting, low visit frequency.',
  },
  'orchard-trees': {
    id: 'orchard-trees', label: 'Orchard', category: 'food-perennial', shape: 'rect',
    defaultWidth: 18, defaultHeight: 14, minWidth: 6, minHeight: 6,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Fruit trees; casts long-term shade, keep clear of solar/annual beds.',
  },
  'berry-rows': {
    id: 'berry-rows', label: 'Berry Rows', category: 'food-perennial', shape: 'rect',
    defaultWidth: 10, defaultHeight: 6, minWidth: 3, minHeight: 3,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Bramble and cane fruit rows, moderate visit frequency for harvest.',
  },
  vineyard: {
    id: 'vineyard', label: 'Vineyard', category: 'food-perennial', shape: 'rect',
    defaultWidth: 16, defaultHeight: 10, minWidth: 6, minHeight: 6,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Trellised vine planting, full sun, south-facing slope preferred.',
  },
  'goat-shelter': {
    id: 'goat-shelter', label: 'Goat Shelter', category: 'animal', shape: 'rect',
    defaultWidth: 5, defaultHeight: 4, minWidth: 2.5, minHeight: 2.5,
    sunNeed: 'partial', noiseLevel: 'moderate', odorLevel: 'strong', needsAccess: true,
    requiresFence: true, description: 'Weatherproof shelter inside the goat paddock.',
  },
  'goat-paddock': {
    id: 'goat-paddock', label: 'Goat Paddock', category: 'animal', shape: 'rect',
    defaultWidth: 16, defaultHeight: 12, minWidth: 8, minHeight: 8,
    sunNeed: 'partial', noiseLevel: 'moderate', odorLevel: 'strong', needsAccess: true,
    requiresFence: true, description: 'Fenced grazing/containment area, kept downwind of the house.',
  },
  'poultry-coop': {
    id: 'poultry-coop', label: 'Poultry Coop & Run', category: 'animal', shape: 'rect',
    defaultWidth: 6, defaultHeight: 5, minWidth: 2, minHeight: 2,
    sunNeed: 'partial', noiseLevel: 'moderate', odorLevel: 'mild', needsAccess: true,
    requiresFence: true, description: 'Hen house and run, close enough for daily egg collection.',
  },
  compost: {
    id: 'compost', label: 'Compost Yard', category: 'utility', shape: 'rect',
    defaultWidth: 4, defaultHeight: 3, minWidth: 2, minHeight: 2,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'strong', needsAccess: true,
    requiresFence: false, description: 'Organic waste processing, kept downwind of leisure/dining areas.',
  },
  'water-tank': {
    id: 'water-tank', label: 'Water Tank', category: 'water', shape: 'circle',
    defaultWidth: 3, defaultHeight: 3, minWidth: 1.5, minHeight: 1.5,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: true, description: 'Bulk water storage, elevated or near the pump for gravity feed.',
  },
  well: {
    id: 'well', label: 'Well', category: 'water', shape: 'circle',
    defaultWidth: 2, defaultHeight: 2, minWidth: 1, minHeight: 1,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: true, description: 'Primary water source; must keep a hard minimum distance from septic.',
  },
  pump: {
    id: 'pump', label: 'Pump House', category: 'water', shape: 'rect',
    defaultWidth: 2, defaultHeight: 2, minWidth: 1, minHeight: 1,
    sunNeed: 'none', noiseLevel: 'moderate', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Pressurizes well/tank water, sited between well and tank.',
  },
  septic: {
    id: 'septic', label: 'Septic System', category: 'utility', shape: 'rect',
    defaultWidth: 5, defaultHeight: 4, minWidth: 3, minHeight: 3,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'mild', needsAccess: false,
    requiresFence: false, description: 'Wastewater treatment field; hard-separated from wells and water sources.',
  },
  'solar-array': {
    id: 'solar-array', label: 'Solar Panels', category: 'energy', shape: 'rect',
    defaultWidth: 8, defaultHeight: 5, minWidth: 3, minHeight: 3,
    sunNeed: 'full', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: false, description: 'Ground-mount PV array; needs unobstructed south-facing exposure.',
  },
  'battery-room': {
    id: 'battery-room', label: 'Battery Room', category: 'energy', shape: 'rect',
    defaultWidth: 3, defaultHeight: 3, minWidth: 2, minHeight: 2,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Energy storage, kept close to inverter and house load center.',
  },
  'inverter-room': {
    id: 'inverter-room', label: 'Inverter Room', category: 'energy', shape: 'rect',
    defaultWidth: 2, defaultHeight: 2, minWidth: 1, minHeight: 1,
    sunNeed: 'none', noiseLevel: 'moderate', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Power conversion equipment, adjacent to battery room and house.',
  },
  generator: {
    id: 'generator', label: 'Backup Generator', category: 'energy', shape: 'rect',
    defaultWidth: 2, defaultHeight: 1.5, minWidth: 1, minHeight: 1,
    sunNeed: 'none', noiseLevel: 'loud', odorLevel: 'mild', needsAccess: true,
    requiresFence: false, description: 'Fuel-fired backup power; needs clearance and noise separation.',
  },
  apiary: {
    id: 'apiary', label: 'Apiary', category: 'animal', shape: 'rect',
    defaultWidth: 5, defaultHeight: 3, minWidth: 2, minHeight: 2,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Beehives for honey and pollination; keep clear of leisure areas and foot traffic.',
  },
  banya: {
    id: 'banya', label: 'Banya', category: 'leisure', shape: 'rect',
    defaultWidth: 5, defaultHeight: 4, minWidth: 3, minHeight: 3,
    sunNeed: 'partial', noiseLevel: 'quiet', odorLevel: 'mild', needsAccess: true,
    requiresFence: false, description: 'Wood-fired sauna/bathhouse; a solid-fuel firebox, so it needs fire-safety clearance like a woodshed.',
  },
  smokehouse: {
    id: 'smokehouse', label: 'Smokehouse', category: 'storage', shape: 'rect',
    defaultWidth: 2.5, defaultHeight: 2, minWidth: 1.5, minHeight: 1.5,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'strong', needsAccess: true,
    requiresFence: false, description: 'Wood-fired meat/fish smoking; open flame and smoke need fire and odor clearance.',
  },
  workshop: {
    id: 'workshop', label: 'Workshop', category: 'storage', shape: 'rect',
    defaultWidth: 6, defaultHeight: 5, minWidth: 3, minHeight: 3,
    sunNeed: 'none', noiseLevel: 'loud', odorLevel: 'mild', needsAccess: true,
    requiresFence: false, description: 'Power-tool workspace; noisy, kept apart from quiet leisure zones.',
  },
  'rainwater-cistern': {
    id: 'rainwater-cistern', label: 'Rainwater Cistern', category: 'water', shape: 'circle',
    defaultWidth: 2.5, defaultHeight: 2.5, minWidth: 1.2, minHeight: 1.2,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: false,
    requiresFence: true, description: 'Collects roof runoff for irrigation; sited close to the house for short downspout runs.',
  },
  dock: {
    id: 'dock', label: 'Dock', category: 'leisure', shape: 'rect',
    defaultWidth: 2.5, defaultHeight: 6, minWidth: 1.5, minHeight: 3,
    sunNeed: 'none', noiseLevel: 'quiet', odorLevel: 'none', needsAccess: true,
    requiresFence: false, description: 'Small pier/boat dock; belongs on calm water — a lake, pond, or slow-moving river section.',
  },
  'micro-hydro': {
    id: 'micro-hydro', label: 'Micro-Hydro Turbine', category: 'energy', shape: 'rect',
    defaultWidth: 2, defaultHeight: 2, minWidth: 1, minHeight: 1,
    sunNeed: 'none', noiseLevel: 'moderate', odorLevel: 'none', needsAccess: true,
    requiresFence: true, description: 'Small water turbine; needs enough flow speed or elevation drop across the waterfront to generate meaningful power.',
  },
};

export const HOUSE_TYPE_IDS = ['house', 'house-l'];

export const OBJECT_LIBRARY_LIST = Object.values(OBJECT_LIBRARY);

export function objectsByCategory(category: ObjectCategory): ObjectLibraryEntry[] {
  return OBJECT_LIBRARY_LIST.filter((o) => o.category === category);
}
