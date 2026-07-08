import type { PlanningMode, StructuredInputs } from '../domain/types';

// Bounded-vocabulary extraction, per PRD §9.5: free text is matched against a
// fixed dictionary rather than sent to an open-ended model, so results stay
// deterministic and explainable. Terms outside this dictionary are surfaced,
// not silently dropped.

const CROP_TERMS: Record<string, string> = {
  potato: 'potato', potatoes: 'potato',
  grain: 'grain', wheat: 'grain', barley: 'grain',
  vegetable: 'vegetable', vegetables: 'vegetable', veggies: 'vegetable',
  berry: 'berries', berries: 'berries', bramble: 'berries', raspberry: 'berries', raspberries: 'berries',
  orchard: 'orchard', fruit: 'orchard', trees: 'orchard',
  vineyard: 'vineyard', grapes: 'vineyard', vines: 'vineyard',
  greenhouse: 'greenhouse',
  hydroponic: 'hydroponic', hydroponics: 'hydroponic',
  'raised bed': 'raised-beds', 'raised beds': 'raised-beds',
};

const ANIMAL_TERMS: Record<string, string> = {
  goat: 'goats', goats: 'goats',
  chicken: 'poultry', chickens: 'poultry', hen: 'poultry', hens: 'poultry', poultry: 'poultry',
};

const INFRA_TERMS: Record<string, string> = {
  solar: 'solar', 'solar panels': 'solar', panels: 'solar',
  well: 'well',
  septic: 'septic',
  generator: 'generator', 'backup power': 'generator',
  'water tank': 'water-tank', tank: 'water-tank',
  compost: 'compost',
  cellar: 'cellar', 'root cellar': 'cellar',
  woodshed: 'woodshed', firewood: 'woodshed',
  garage: 'garage',
  barn: 'barn',
};

const STYLE_TERMS: Record<string, number> = {
  beautiful: 20, ornamental: 25, decorative: 15, elegant: 15,
  utilitarian: -25, practical: -15, functional: -10, minimal: -10,
  ergonomic: -5, compact: -10, easy: -5,
};

const MODE_TERMS: Record<string, PlanningMode> = {
  productive: 'production-max', production: 'production-max', maximize: 'production-max', maximum: 'production-max',
  'low maintenance': 'minimum-maintenance', 'minimum maintenance': 'minimum-maintenance', maintenance: 'minimum-maintenance',
  beautiful: 'beauty-balanced', balanced: 'beauty-balanced', beauty: 'beauty-balanced',
  safe: 'safety-first', safety: 'safety-first', secure: 'safety-first',
};

const HOUSEHOLD_RE = /family of (\d+)|(\d+)\s*(?:people|person|adults)/i;

export interface FreeTextExtraction {
  crops: string[];
  animals: string[];
  infrastructure: string[];
  aestheticDelta: number;
  suggestedModes: PlanningMode[];
  householdSize?: number;
  unrecognizedTerms: string[];
}

function findAll(text: string, dict: Record<string, string>): { matches: string[]; consumed: string[] } {
  const matches = new Set<string>();
  const consumed: string[] = [];
  for (const [term, value] of Object.entries(dict)) {
    const re = new RegExp(`\\b${term}\\b`, 'i');
    if (re.test(text)) {
      matches.add(value);
      consumed.push(term);
    }
  }
  return { matches: [...matches], consumed };
}

export function parseFreeText(text: string): FreeTextExtraction {
  const lower = text.toLowerCase();
  const crops = findAll(lower, CROP_TERMS);
  const animals = findAll(lower, ANIMAL_TERMS);
  const infra = findAll(lower, INFRA_TERMS);

  let aestheticDelta = 0;
  const styleConsumed: string[] = [];
  for (const [term, delta] of Object.entries(STYLE_TERMS)) {
    if (new RegExp(`\\b${term}\\b`, 'i').test(lower)) {
      aestheticDelta += delta;
      styleConsumed.push(term);
    }
  }

  const modes = new Set<PlanningMode>();
  const modeConsumed: string[] = [];
  for (const [term, mode] of Object.entries(MODE_TERMS)) {
    if (new RegExp(`\\b${term}\\b`, 'i').test(lower)) {
      modes.add(mode);
      modeConsumed.push(term);
    }
  }

  const householdMatch = lower.match(HOUSEHOLD_RE);
  const householdSize = householdMatch
    ? Number(householdMatch[1] ?? householdMatch[2])
    : undefined;

  const consumedWords = new Set(
    [...crops.consumed, ...animals.consumed, ...infra.consumed, ...styleConsumed, ...modeConsumed]
      .join(' ')
      .toLowerCase()
      .split(/\s+/),
  );
  const words = lower.replace(/[^a-z\s]/g, '').split(/\s+/).filter(Boolean);
  const stopwords = new Set(['a', 'an', 'the', 'and', 'for', 'with', 'of', 'to', 'i', 'want', 'need', 'something', 'is', 'that', 'my']);
  const unrecognizedTerms = [...new Set(words.filter((w) => !consumedWords.has(w) && !stopwords.has(w) && w.length > 3))].slice(0, 12);

  return {
    crops: crops.matches,
    animals: animals.matches,
    infrastructure: infra.matches,
    aestheticDelta,
    suggestedModes: [...modes],
    householdSize,
    unrecognizedTerms,
  };
}

export function mergeFreeTextIntoStructured(
  base: StructuredInputs,
  extraction: FreeTextExtraction,
): StructuredInputs {
  return {
    ...base,
    householdSize: base.householdSize || extraction.householdSize || 1,
    crops: [...new Set([...base.crops, ...extraction.crops])],
    animals:
      extraction.animals.length > 0 && base.animals.length === 0
        ? extraction.animals.map((type) => ({ type, count: type === 'goats' ? 4 : 6 }))
        : base.animals,
    infrastructure: [...new Set([...base.infrastructure, ...extraction.infrastructure])],
    aestheticPreference: clampPct(base.aestheticPreference + extraction.aestheticDelta),
  };
}

function clampPct(v: number): number {
  return Math.max(0, Math.min(100, v));
}
