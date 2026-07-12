import { v4 as uuid } from 'uuid';
import type { Project, StructuredInputs } from '../domain/types';

export interface ProjectTemplate {
  id: string;
  nameKey: string;
  descriptionKey: string;
  width: number;
  height: number;
  structuredInputs: StructuredInputs;
  freeTextKey: string;
}

// A handful of realistic starting points so a new project doesn't begin as a
// blank form — each pre-fills a plot size and a full structured brief that
// already produces a sensible layout, which the user can then tweak instead
// of building up from nothing.
export const PROJECT_TEMPLATES: ProjectTemplate[] = [
  {
    id: 'blank',
    nameKey: 'template.blank.name',
    descriptionKey: 'template.blank.description',
    width: 40,
    height: 30,
    structuredInputs: {
      householdSize: 2,
      climateZone: 'temperate',
      terrainSlope: 'flat',
      soilType: 'loam',
      waterSources: [],
      gridPower: true,
      priorities: ['beauty-balanced'],
      animals: [],
      crops: [],
      infrastructure: [],
      aestheticPreference: 50,
      houseSizePreset: 'medium',
      houseShape: 'rect',
    },
    freeTextKey: '',
  },
  {
    id: 'small-homestead',
    nameKey: 'template.smallHomestead.name',
    descriptionKey: 'template.smallHomestead.description',
    width: 46,
    height: 34,
    structuredInputs: {
      householdSize: 2,
      climateZone: 'temperate',
      terrainSlope: 'gentle',
      soilType: 'loam',
      waterSources: ['municipal'],
      gridPower: true,
      priorities: ['minimum-maintenance', 'beauty-balanced'],
      animals: [{ type: 'poultry', count: 6 }],
      crops: ['vegetable', 'potato', 'raised-beds'],
      infrastructure: ['well', 'septic', 'solar'],
      aestheticPreference: 55,
      houseSizePreset: 'small',
      houseShape: 'rect',
    },
    freeTextKey: 'template.smallHomestead.freeText',
  },
  {
    id: 'off-grid-cabin',
    nameKey: 'template.offGridCabin.name',
    descriptionKey: 'template.offGridCabin.description',
    width: 34,
    height: 28,
    structuredInputs: {
      householdSize: 1,
      climateZone: 'continental',
      terrainSlope: 'gentle',
      soilType: 'rocky',
      waterSources: ['rain catchment'],
      gridPower: false,
      priorities: ['minimum-maintenance', 'safety-first'],
      animals: [],
      crops: [],
      infrastructure: ['solar', 'well', 'generator', 'rainwater-cistern', 'woodshed'],
      aestheticPreference: 40,
      houseSizePreset: 'small',
      houseShape: 'rect',
    },
    freeTextKey: 'template.offGridCabin.freeText',
  },
  {
    id: 'market-garden',
    nameKey: 'template.marketGarden.name',
    descriptionKey: 'template.marketGarden.description',
    width: 55,
    height: 40,
    structuredInputs: {
      householdSize: 3,
      climateZone: 'mediterranean',
      terrainSlope: 'flat',
      soilType: 'loam',
      waterSources: ['well', 'municipal'],
      gridPower: true,
      priorities: ['production-max', 'beauty-balanced'],
      animals: [],
      crops: ['vegetable', 'greenhouse', 'hydroponic', 'raised-beds', 'orchard', 'berries'],
      infrastructure: ['well', 'water-tank', 'solar', 'workshop'],
      aestheticPreference: 45,
      houseSizePreset: 'medium',
      houseShape: 'rect',
    },
    freeTextKey: 'template.marketGarden.freeText',
  },
  {
    id: 'large-family-farm',
    nameKey: 'template.largeFamilyFarm.name',
    descriptionKey: 'template.largeFamilyFarm.description',
    width: 100,
    height: 60,
    structuredInputs: {
      householdSize: 7,
      climateZone: 'continental',
      terrainSlope: 'gentle',
      soilType: 'loam',
      waterSources: ['well', 'rain catchment'],
      gridPower: true,
      priorities: ['beauty-balanced', 'production-max'],
      animals: [{ type: 'goats', count: 8 }, { type: 'poultry', count: 12 }],
      crops: ['potato', 'grain', 'vegetable', 'orchard', 'berries', 'vineyard'],
      infrastructure: ['solar', 'well', 'septic', 'generator', 'barn', 'workshop', 'garage'],
      aestheticPreference: 55,
      houseSizePreset: 'large',
      houseShape: 'lshape',
    },
    freeTextKey: 'template.largeFamilyFarm.freeText',
  },
];

export function buildProjectFromTemplate(template: ProjectTemplate, name: string, width = template.width, height = template.height): Project {
  const now = new Date().toISOString();
  return {
    id: uuid(),
    name,
    createdAt: now,
    updatedAt: now,
    brief: {
      structuredInputs: { ...template.structuredInputs, animals: template.structuredInputs.animals.map((a) => ({ ...a })) },
      freeText: template.freeTextKey ? FREE_TEXT_FALLBACK[template.freeTextKey] ?? '' : '',
    },
    plot: {
      id: `plot-${uuid()}`,
      boundary: [
        { x: 0, y: 0 },
        { x: width, y: 0 },
        { x: width, y: height },
        { x: 0, y: height },
      ],
      northAngleDeg: 0,
      climateZone: template.structuredInputs.climateZone,
      terrainSlope: template.structuredInputs.terrainSlope,
      soilType: template.structuredInputs.soilType,
      waterSources: [...template.structuredInputs.waterSources],
      gridPower: template.structuredInputs.gridPower,
      existingObjects: [],
    },
    variants: [],
    activeVariantId: '',
    stylePresetId: 'architectural-light',
  };
}

// English fallback free-text briefs, keyed the same way as translations.ts —
// translated free text isn't fed to the engine differently per locale (the
// bounded-vocabulary parser only understands English terms today), so this
// is just the human-readable placeholder shown/edited in the brief panel.
const FREE_TEXT_FALLBACK: Record<string, string> = {
  'template.smallHomestead.freeText':
    'A small, low-maintenance homestead for 2 people with a vegetable garden, potatoes, chickens, a well, septic and solar power.',
  'template.offGridCabin.freeText':
    'A small off-grid cabin for 1 person, no grid power, solar with battery backup, a generator for cloudy days, a well, rainwater cistern and a woodshed for heating.',
  'template.marketGarden.freeText':
    'A production-focused market garden for a small farm business — greenhouse, hydroponic towers, raised beds, an orchard and berries, a well and water tank for irrigation.',
  'template.largeFamilyFarm.freeText':
    'A large multi-generational family farm for 7 people with potatoes, grain, orchard, berries, a vineyard, goats and poultry, solar, a well, septic, backup generator, barn, workshop and garage.',
};
