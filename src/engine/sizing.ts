import type { PlanningMode, StructuredInputs } from '../domain/types';
import { OBJECT_LIBRARY } from '../domain/objectLibrary';

export interface ProgramItem {
  typeId: string;
  width: number;
  height: number;
  count: number; // how many separate instances to place (e.g. 2 berry rows)
  metadata: Record<string, unknown>;
}

const CROP_TO_TYPE: Record<string, string> = {
  potato: 'potato-area',
  grain: 'grain-field',
  vegetable: 'vegetable-area',
  berries: 'berry-rows',
  orchard: 'orchard-trees',
  vineyard: 'vineyard',
  greenhouse: 'greenhouse',
  hydroponic: 'hydroponic-tower',
  'raised-beds': 'raised-beds',
};

const INFRA_TO_TYPES: Record<string, string[]> = {
  solar: ['solar-array', 'battery-room', 'inverter-room'],
  well: ['well', 'pump'],
  septic: ['septic'],
  'water-tank': ['water-tank'],
  generator: ['generator'],
  compost: ['compost'],
  cellar: ['cellar'],
  woodshed: ['woodshed'],
  garage: ['garage'],
  barn: ['barn'],
  pool: ['pool'],
  gazebo: ['gazebo'],
  apiary: ['apiary'],
  banya: ['banya'],
  smokehouse: ['smokehouse'],
  workshop: ['workshop'],
  'rainwater-cistern': ['rainwater-cistern'],
};

const MODE_SCALE: Record<PlanningMode, number> = {
  'production-max': 1.3,
  'minimum-maintenance': 0.75,
  'beauty-balanced': 1.0,
  'safety-first': 0.9,
};

const HOUSE_SIZE_SCALE: Record<StructuredInputs['houseSizePreset'], number> = {
  small: 0.55,
  medium: 1,
  large: 1.65,
};

// Object defaults are sized for a household of ~3; scale modestly around that baseline.
function perPersonScale(householdSize: number, base: number): number {
  const factor = Math.max(0.6, Math.min(1.8, householdSize / 3));
  return base * factor;
}

export function buildProgram(inputs: StructuredInputs, mode: PlanningMode): ProgramItem[] {
  const items: ProgramItem[] = [];
  // Mode scaling is applied only to food-producing zones — "maximum
  // productivity" should grow orchards and fields, not inflate the garage.
  const foodModeScale = MODE_SCALE[mode];

  const houseTypeId = inputs.houseShape === 'lshape' ? 'house-l' : 'house';
  items.push(sized(houseTypeId, 1, HOUSE_SIZE_SCALE[inputs.houseSizePreset] ?? 1));
  if (inputs.aestheticPreference >= 35) items.push(sized('patio', 1, 1));
  items.push(sized('shed', 1, 1));

  // Staples (potato/grain/vegetable) are sized to household subsistence need
  // and held constant across modes; the surplus/quality-of-life zones
  // (orchard, berries, vineyard, greenhouse) are what "production-maximizing"
  // actually grows — this keeps the mode's effect legible instead of
  // uniformly inflating everything, which starved orchard space in testing.
  for (const crop of inputs.crops) {
    const typeId = CROP_TO_TYPE[crop];
    if (!typeId) continue;
    const entry = OBJECT_LIBRARY[typeId];
    const scaleFactor = ['potato-area', 'grain-field', 'vegetable-area'].includes(typeId)
      ? perPersonScale(inputs.householdSize, 1)
      : foodModeScale;
    items.push(sized(typeId, 1, scaleFactor, entry));
  }

  for (const animal of inputs.animals) {
    if (animal.type === 'goats' && animal.count > 0) {
      const paddockScale = Math.max(1, animal.count / 4);
      items.push(sized('goat-shelter', 1, Math.max(1, animal.count / 4) * 0.9));
      items.push(sized('goat-paddock', 1, paddockScale, undefined, { animalCount: animal.count, animalType: 'goats' }));
    }
    if (animal.type === 'poultry' && animal.count > 0) {
      const scale = Math.max(1, animal.count / 8);
      items.push(sized('poultry-coop', 1, scale, undefined, { animalCount: animal.count, animalType: 'poultry' }));
    }
  }

  for (const infra of inputs.infrastructure) {
    const typeIds = INFRA_TO_TYPES[infra];
    if (!typeIds) continue;
    for (const typeId of typeIds) items.push(sized(typeId, 1, 1));
  }

  // Compost is near-universal once any food production is requested.
  const hasFoodZone = inputs.crops.length > 0;
  if (hasFoodZone && !inputs.infrastructure.includes('compost')) {
    items.push(sized('compost', 1, 1));
  }

  return items;
}

function sized(
  typeId: string,
  count: number,
  scale: number,
  entryOverride?: (typeof OBJECT_LIBRARY)[string],
  metadata: Record<string, unknown> = {},
): ProgramItem {
  const entry = entryOverride ?? OBJECT_LIBRARY[typeId];
  const sqrtScale = Math.sqrt(scale);
  return {
    typeId,
    width: Math.max(entry.minWidth, entry.defaultWidth * sqrtScale),
    height: Math.max(entry.minHeight, entry.defaultHeight * sqrtScale),
    count,
    metadata,
  };
}
