// Core domain model for Homestead Planner AI.
// All spatial units are meters unless suffixed otherwise (e.g. widthPx).

export type Point = { x: number; y: number };

export type ZoneCategory =
  | 'residential'
  | 'access'
  | 'food-annual'
  | 'food-perennial'
  | 'greenhouse'
  | 'animal'
  | 'utility'
  | 'water'
  | 'energy'
  | 'storage'
  | 'leisure'
  | 'future-expansion';

export type ObjectCategory = ZoneCategory | 'fence' | 'path';

export type PlanningMode =
  | 'production-max'
  | 'minimum-maintenance'
  | 'beauty-balanced'
  | 'safety-first';

export type ClimateZone =
  | 'temperate'
  | 'continental'
  | 'mediterranean'
  | 'arid'
  | 'subtropical'
  | 'cold';

export type TerrainSlope = 'flat' | 'gentle' | 'steep';

export type SoilType = 'loam' | 'clay' | 'sandy' | 'rocky' | 'unknown';

export type WaterfrontType = 'river' | 'lake' | 'pond';
export type WaterfrontEdge = 'north' | 'south' | 'east' | 'west';

export interface Waterfront {
  type: WaterfrontType;
  edge: WaterfrontEdge; // which boundary edge the water runs along
  widthM: number; // how much of the plot's depth from that edge is water
  flowSpeedMps?: number; // river only — for micro-hydro feasibility
  elevationDropM?: number; // river/lake outlet — for micro-hydro feasibility
}

export interface StructuredInputs {
  householdSize: number;
  climateZone: ClimateZone;
  terrainSlope: TerrainSlope;
  soilType: SoilType;
  waterSources: string[];
  gridPower: boolean;
  priorities: PlanningMode[]; // ranked, first = highest priority
  animals: { type: string; count: number }[];
  crops: string[];
  infrastructure: string[]; // 'solar' | 'well' | 'septic' | 'greenhouse' | ...
  aestheticPreference: number; // 0 = utilitarian, 100 = ornamental
  houseSizePreset: 'small' | 'medium' | 'large';
  houseShape: 'rect' | 'lshape';
}

export interface Brief {
  structuredInputs: StructuredInputs;
  freeText: string;
  unrecognizedTerms?: string[];
}

export interface PlotObject_Existing {
  id: string;
  type: string;
  transform: Transform;
  label: string;
}

export interface Plot {
  id: string;
  boundary: Point[]; // polygon, CW or CCW, in meters
  northAngleDeg: number; // rotation of "up" relative to true north
  climateZone: ClimateZone;
  terrainSlope: TerrainSlope;
  soilType: SoilType;
  waterSources: string[];
  gridPower: boolean;
  waterfront?: Waterfront;
  existingObjects: PlotObject_Existing[];
}

export interface Transform {
  x: number; // center x, meters
  y: number; // center y, meters
  width: number; // meters
  height: number; // meters
  rotationDeg: number;
}

export interface Zone {
  id: string;
  category: ZoneCategory;
  boundary: Point[]; // polygon in meters, absolute plot coordinates
  label: string;
  colorOverride?: string;
  metadata: Record<string, unknown>;
  locked: boolean;
}

export interface PlanObject {
  id: string;
  zoneId?: string;
  typeId: string; // references ObjectLibrary catalog entry
  category: ObjectCategory;
  transform: Transform;
  label: string;
  locked: boolean;
  layerId: ObjectCategory;
  metadata: Record<string, unknown>;
}

export interface PathEntity {
  id: string;
  points: Point[];
  widthM: number;
  surfaceType: 'gravel' | 'paved' | 'mulch' | 'grass';
  category: 'access' | 'service';
}

export interface Fence {
  id: string;
  points: Point[];
  fenceType: 'perimeter' | 'paddock' | 'garden' | 'decorative';
  gated: boolean;
}

export interface UtilityNode {
  id: string;
  type: 'well' | 'septic' | 'power-meter' | 'water-tank' | 'solar-array' | 'battery-room' | 'inverter' | 'generator';
  position: Point;
  connections: string[]; // UtilityNode ids
}

export type ConstraintKind = 'adjacency' | 'separation' | 'sunlight' | 'access' | 'safety';

export interface Constraint {
  id: string;
  kind: ConstraintKind;
  // Matches an object if its typeId or category appears in these lists.
  subjectTypes: string[];
  relatedTypes: string[];
  minDistance?: number; // 'separation' rules: violated if closer than this
  maxDistance?: number; // 'adjacency' rules: violated if farther than this
  hard: boolean; // hard constraints are enforced as placement filters, not just warnings
  severity: WarningSeverity;
  message: string;
}

export type WarningSeverity = 'info' | 'caution' | 'critical';

export interface Warning {
  id: string;
  severity: WarningSeverity;
  message: string; // English fallback, used when messageKey is absent
  messageKey?: string;
  messageParams?: Record<string, string | number>;
  ruleId: string;
  objectIds: string[];
  suggestedFix?: { label: string; action: string };
}

export interface AnalyticsSnapshot {
  totalAreaM2: number;
  allocatedAreaM2: number;
  unallocatedAreaM2: number;
  byCategory: { category: ZoneCategory; areaM2: number; percent: number }[];
  estimatedFoodProductionScore: number; // 0-100
  maintenanceComplexityScore: number; // 0-100, higher = more upkeep
  computedAt: string;
}

export interface EditSnapshot {
  zones: Zone[];
  objects: PlanObject[];
  paths: PathEntity[];
  fences: Fence[];
  utilityNodes: UtilityNode[];
}

export interface LayoutVariant {
  id: string;
  strategyLabel: string;
  mode: PlanningMode;
  seed: number;
  zones: Zone[];
  objects: PlanObject[];
  paths: PathEntity[];
  fences: Fence[];
  utilityNodes: UtilityNode[];
  analytics: AnalyticsSnapshot;
  warnings: Warning[];
  history: { past: EditSnapshot[]; future: EditSnapshot[] };
}

export type StylePresetId = 'architectural-light' | 'architectural-dark';

export interface StylePreset {
  id: StylePresetId;
  name: string;
  paletteMap: Record<ZoneCategory, string>;
}

export interface Project {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  brief: Brief;
  plot: Plot;
  variants: LayoutVariant[];
  activeVariantId: string;
  stylePresetId: StylePresetId;
}

export type VisualizationMode =
  | 'schematic'
  | 'design'
  | 'utilities'
  | 'seasonal'
  | 'rationale';

export type Season = 'spring' | 'summer' | 'autumn' | 'winter';
