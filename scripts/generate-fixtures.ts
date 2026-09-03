/**
 * Generates the golden fixtures the Swift engine port is verified against.
 *
 * Generation is deterministic given a plot, a brief, a mode and a seed
 * (`mulberry32`, src/engine/placement.ts), so the Swift implementation must
 * reproduce these files exactly. Each fixture is self-contained: it carries
 * the input alongside the output, so the Swift test reconstructs the project
 * without knowing anything about this script.
 *
 * Run with `npm run fixtures`.
 */
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import type { Brief, LayoutVariant, PlanningMode, Plot, Project } from '../src/domain/types';
import { OBJECT_LIBRARY } from '../src/domain/objectLibrary';
import { CONSTRAINTS, BOUNDARY_SETBACKS } from '../src/domain/constraints';
import { generateVariant } from '../src/engine/generate';
import { mulberry32, placeObjects } from '../src/engine/placement';
import { buildProgram } from '../src/engine/sizing';
import { parseFreeText, mergeFreeTextIntoStructured } from '../src/engine/textParser';
import { buildLShapeBoundary, buildRectBoundary } from '../src/engine/plotShapes';

const OUT_DIR = join(import.meta.dirname, '..', 'fixtures');

const MODES: PlanningMode[] = ['minimum-maintenance', 'production-max', 'beauty-balanced', 'safety-first'];
const SEEDS = [42, 59];

interface Scenario {
  name: string;
  /** Why this scenario is in the matrix — kept in the fixture for the reader. */
  covers: string;
  plot: Plot;
  brief: Brief;
}

function plot(patch: Partial<Plot> & Pick<Plot, 'boundary'>): Plot {
  return {
    id: 'plot-fixture',
    northAngleDeg: 0,
    climateZone: 'temperate',
    terrainSlope: 'flat',
    soilType: 'loam',
    waterSources: [],
    gridPower: true,
    existingObjects: [],
    ...patch,
  };
}

function brief(patch: Partial<Brief['structuredInputs']>, freeText = ''): Brief {
  return {
    freeText,
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
      ...patch,
    },
  };
}

const SCENARIOS: Scenario[] = [
  {
    name: 'minimal',
    covers: 'Smallest sane plot, empty program — the floor of the placement search.',
    plot: plot({ boundary: buildRectBoundary(30, 30) }),
    brief: brief({ crops: ['vegetable'] }),
  },
  {
    name: 'family',
    covers: 'The realistic middle case: animals, crops and utilities together.',
    plot: plot({ boundary: buildRectBoundary(50, 42) }),
    brief: brief({
      householdSize: 4,
      animals: [
        { type: 'goats', count: 4 },
        { type: 'poultry', count: 6 },
      ],
      crops: ['potato', 'vegetable', 'berries', 'orchard'],
      infrastructure: ['solar', 'well', 'septic', 'compost', 'woodshed'],
    }),
  },
  {
    name: 'lshape',
    covers: 'Non-convex boundary — placement must respect the notch, not the bounding box.',
    plot: plot({ boundary: buildLShapeBoundary(60, 45, 20, 15, 'ne') }),
    brief: brief({
      householdSize: 3,
      crops: ['orchard', 'greenhouse', 'vineyard'],
      infrastructure: ['well', 'cellar', 'garage'],
    }),
  },
  {
    name: 'waterfront',
    covers: 'Water edge plus the infrastructure only a waterfront unlocks.',
    plot: plot({
      boundary: buildRectBoundary(50, 42),
      waterfront: { type: 'river', edge: 'west', widthM: 10, flowSpeedMps: 0.8, elevationDropM: 1.5 },
    }),
    brief: brief({
      householdSize: 3,
      crops: ['vegetable', 'berries'],
      infrastructure: ['dock', 'micro-hydro', 'water-tank', 'banya'],
    }),
  },
  {
    name: 'sloped',
    covers: 'Elevation model engaged — terrain-sensitive placement and contour-driven rules.',
    plot: plot({
      boundary: buildRectBoundary(50, 42),
      terrainSlope: 'gentle',
      elevation: { highEdge: 'north', dropM: 3 },
    }),
    brief: brief({
      householdSize: 4,
      terrainSlope: 'gentle',
      crops: ['potato', 'raised-beds', 'orchard'],
      infrastructure: ['solar', 'well', 'rainwater-cistern'],
    }),
  },
  {
    name: 'overloaded',
    covers: 'Program that cannot fit — exercises the unplaced/over-capacity path.',
    plot: plot({ boundary: buildRectBoundary(25, 20) }),
    brief: brief(
      {
        householdSize: 8,
        animals: [
          { type: 'goats', count: 12 },
          { type: 'poultry', count: 30 },
        ],
        crops: ['potato', 'grain', 'vegetable', 'berries', 'orchard', 'vineyard', 'greenhouse'],
        infrastructure: ['solar', 'well', 'septic', 'generator', 'barn', 'garage', 'pool', 'workshop'],
      },
      'we also want a big apiary and a smokehouse',
    ),
  },
];

/**
 * Three parts of `generateVariant`'s output are not a function of its inputs:
 * a fresh uuid for the variant, a uuid suffix on unplaced warnings, and
 * `analytics.computedAt` — a wall clock reading. All three are projected away
 * so a fixture stays stable across runs, and all three are artefacts the
 * Swift port drops rather than reproduces: ids derive from the seed, and
 * computed analytics need no timestamp because they are never stored.
 */
function normalize(variant: LayoutVariant) {
  const { id: _id, history: _history, analytics, ...rest } = variant;
  const { computedAt: _computedAt, ...analyticsRest } = analytics;
  return {
    ...rest,
    analytics: analyticsRest,
    warnings: variant.warnings.map((w) => ({
      ...w,
      id: w.id.startsWith('warn-unplaced-') ? w.id.replace(/-[0-9a-f]{8}$/, '') : w.id,
    })),
  };
}

function main() {
  rmSync(OUT_DIR, { recursive: true, force: true });
  mkdirSync(OUT_DIR, { recursive: true });

  const index: { file: string; scenario: string; mode: PlanningMode; seed: number }[] = [];

  for (const scenario of SCENARIOS) {
    for (const mode of MODES) {
      for (const seed of SEEDS) {
        const project: Project = {
          id: `project-${scenario.name}`,
          name: scenario.name,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          brief: scenario.brief,
          plot: scenario.plot,
          variants: [],
          activeVariantId: '',
          stylePresetId: 'architectural-light',
        };

        const file = `${scenario.name}--${mode}--${seed}.json`;
        writeFileSync(
          join(OUT_DIR, file),
          JSON.stringify(
            {
              covers: scenario.covers,
              input: { plot: scenario.plot, brief: scenario.brief, mode, seed },
              output: normalize(generateVariant(project, mode, seed)),
            },
            null,
            1,
          ) + '\n',
        );
        index.push({ file, scenario: scenario.name, mode, seed });
      }
    }
  }

  writeFileSync(join(OUT_DIR, 'index.json'), JSON.stringify({ fixtures: index }, null, 1) + '\n');

  // Every placement decision is downstream of this generator, so a Swift port
  // that diverges here diverges everywhere. Reference draws are emitted
  // separately from the layouts so the failure points at the cause rather
  // than at 48 mismatched plans.
  const rng = Object.fromEntries(
    [42, 59, 0, 1, 2147483647, 123456789].map((seed) => {
      const rand = mulberry32(seed);
      return [String(seed), Array.from({ length: 8 }, () => rand())];
    }),
  );
  writeFileSync(join(OUT_DIR, 'rng.json'), JSON.stringify({ mulberry32: rng }, null, 1) + '\n');

  // The object catalog is data, and the Swift copy is hand-owned code that
  // will evolve past this one. Emitting it here gives the port a parity test,
  // so a transcription slip in 30 entries of dimensions and flags fails
  // loudly instead of quietly mis-sizing a paddock.
  writeFileSync(join(OUT_DIR, 'objectLibrary.json'), JSON.stringify(OBJECT_LIBRARY, null, 1) + '\n');
  writeFileSync(
    join(OUT_DIR, 'constraints.json'),
    JSON.stringify({ constraints: CONSTRAINTS, boundarySetbacks: BOUNDARY_SETBACKS }, null, 1) + '\n',
  );

  // placeObjects in isolation, for the same 48 (scenario, mode, seed)
  // combinations, decoupled from paths/fences/analytics/warnings so
  // placement.ts can be verified before the rest of the pipeline exists.
  // This is the single highest-risk file in the port: every rejected
  // candidate still draws from the shared RNG before being discarded, so a
  // one-iteration drift in the search grid desyncs every draw after it —
  // exact equality here, including generated ids, is the only real proof the
  // draw sequence stayed aligned.
  const placementFixtures: unknown[] = [];
  for (const scenario of SCENARIOS) {
    for (const mode of MODES) {
      for (const seed of SEEDS) {
        const extraction = parseFreeText(scenario.brief.freeText);
        const mergedInputs = mergeFreeTextIntoStructured(scenario.brief.structuredInputs, extraction);
        const program = buildProgram(mergedInputs, mode);
        const result = placeObjects(scenario.plot, program, mode, seed);
        placementFixtures.push({
          scenario: scenario.name,
          mode,
          seed,
          input: { plot: scenario.plot, program },
          output: result,
        });
      }
    }
  }
  writeFileSync(join(OUT_DIR, 'placement.json'), JSON.stringify(placementFixtures, null, 1) + '\n');

  console.log(`Wrote ${index.length} fixtures to ${OUT_DIR}`);
}

main();
