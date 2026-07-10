import type { ClimateZone, WarningSeverity } from './types';

export interface CropClimateNote {
  crop: string; // matches StructuredInputs.crops entries
  questionableZones: ClimateZone[];
  severity: WarningSeverity;
  message: string;
}

// Deliberately conservative, general-knowledge guidance — real feasibility
// depends heavily on irrigation, cultivar choice, and microclimate, none of
// which this planner models. Framed as "worth double-checking," not a
// prohibition.
export const CROP_CLIMATE_NOTES: CropClimateNote[] = [
  {
    crop: 'vineyard',
    questionableZones: ['cold'],
    severity: 'caution',
    message: 'Grapevines usually need a longer, warmer growing season than a cold climate zone provides — consider cold-hardy cultivars or a greenhouse.',
  },
  {
    crop: 'grain',
    questionableZones: ['arid'],
    severity: 'info',
    message: 'Grain in an arid zone will likely need irrigation to reach reasonable yields.',
  },
  {
    crop: 'orchard',
    questionableZones: ['arid'],
    severity: 'caution',
    message: 'Most fruit trees need more consistent moisture than an arid climate provides without irrigation.',
  },
  {
    crop: 'berries',
    questionableZones: ['arid', 'subtropical'],
    severity: 'caution',
    message: 'Most berry brambles prefer cooler, moister conditions than this climate zone typically offers.',
  },
  {
    crop: 'potato',
    questionableZones: ['subtropical', 'arid'],
    severity: 'info',
    message: 'Potatoes generally yield better in cooler climates — expect lower yields or a need for irrigation here.',
  },
];
