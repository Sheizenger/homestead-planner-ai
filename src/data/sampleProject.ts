import { v4 as uuid } from 'uuid';
import type { Project } from '../domain/types';

export function createSampleProject(): Project {
  const now = new Date().toISOString();
  return {
    id: uuid(),
    name: 'Family Homestead — 21 Sotok',
    createdAt: now,
    updatedAt: now,
    brief: {
      structuredInputs: {
        householdSize: 3,
        climateZone: 'temperate',
        terrainSlope: 'gentle',
        soilType: 'loam',
        waterSources: ['rain catchment', 'municipal'],
        gridPower: true,
        priorities: ['beauty-balanced', 'production-max'],
        animals: [{ type: 'goats', count: 4 }],
        crops: ['potato', 'grain', 'orchard', 'berries', 'greenhouse'],
        infrastructure: ['solar', 'well', 'septic'],
        aestheticPreference: 55,
        houseSizePreset: 'medium',
        houseShape: 'rect',
      },
      freeText:
        'I want a family homestead for 3 people with potatoes, grain, orchard, berries, goats, ' +
        'a greenhouse and solar. I would like it to be ergonomic and easy to maintain, but not ' +
        'purely utilitarian — the plot should look beautiful too.',
    },
    plot: {
      id: 'plot-sample',
      boundary: [
        { x: 0, y: 0 },
        { x: 60, y: 0 },
        { x: 60, y: 35 },
        { x: 0, y: 35 },
      ],
      northAngleDeg: 0,
      climateZone: 'temperate',
      terrainSlope: 'gentle',
      soilType: 'loam',
      waterSources: ['rain catchment', 'municipal'],
      gridPower: true,
      existingObjects: [],
    },
    variants: [],
    activeVariantId: '',
    stylePresetId: 'architectural-light',
  };
}

export function createBlankProject(name: string, width: number, height: number): Project {
  const now = new Date().toISOString();
  return {
    id: uuid(),
    name,
    createdAt: now,
    updatedAt: now,
    brief: {
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
      freeText: '',
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
      climateZone: 'temperate',
      terrainSlope: 'flat',
      soilType: 'loam',
      waterSources: [],
      gridPower: true,
      existingObjects: [],
    },
    variants: [],
    activeVariantId: '',
    stylePresetId: 'architectural-light',
  };
}
