<p align="center"><img src="public/logo.svg" alt="Homestead Planner AI" width="96" height="96" /></p>

# Homestead Planner AI

A desktop-first web app that turns a natural-language + structured brief about
a rural/homestead property into an editable, analyzed 2D site plan. See
[`PRD.md`](./PRD.md) for the full product spec this implementation follows.

## Running it

```bash
npm install
npm run dev      # dev server
npm run build    # typecheck + production build
npm run test     # vitest — placement/generation engine unit tests
```

Opens with a preloaded sample project ("Family Homestead — 21 Sotok") and
generates 3 layout variants automatically on first load.

## Architecture

- **`src/domain`** — the data model (`types.ts`), the object catalog
  (`objectLibrary.ts`), planning rules (`constraints.ts`), and category
  colors/labels (`categories.ts`). This is the single source of truth every
  other layer reads from.
- **`src/engine`** — pure, framework-free functions:
  - `textParser.ts` — bounded-vocabulary extraction from the free-text brief
    (deliberately not an LLM call — keeps generation deterministic and
    explainable; see PRD §9.5).
  - `sizing.ts` — turns structured inputs into a list of objects to place,
    sized by household need and planning mode.
  - `placement.ts` — the greedy, constraint-scored placement algorithm.
    Places structures/utilities as anchors, then works through animals and
    food zones largest-first within each priority tier so big fields don't
    get starved of space by smaller ones placed earlier.
  - `generate.ts` — orchestrates the above into 3 `LayoutVariant`s (Compact &
    Efficient / Production-Maximizing / Beauty-Balanced, or the user's chosen
    mode swapped in) plus the future-expansion reserve zone.
  - `analytics.ts` / `warnings.ts` — area accounting and constraint/overlap/
    capacity warnings, recomputed from `CONSTRAINTS` so scoring and warnings
    never drift apart. Also checks plot-boundary setbacks
    (`BOUNDARY_SETBACKS`) and a household-size-vs-plot-area guideline
    (`RECOMMENDED_M2_PER_PERSON`).
  - `pathsAndFences.ts` — synthesizes a gate point on the road-facing
    boundary edge, a paved driveway (gate → garage), a narrower entrance
    walk (gate → house), and gravel garden paths to other frequently-visited
    zones; fences wrap anything with `requiresFence: true`.
  - `exporters.ts` — SVG → PNG/PDF rasterization and JSON serialization.
  - `costs.ts` — rough cost estimate (land + per-object construction +
    annual upkeep) for a location, using `domain/costData.ts`'s region
    table (land price + labor/maintenance index per country/state) and
    static USD/EUR/RUB exchange rates.
- **`src/state/projectStore.ts`** — Zustand store. Each `LayoutVariant` owns
  its own undo/redo history stack (immutable snapshots), so switching
  variants never corrupts editing history.
- **`src/components`** — `canvas/PlanCanvas.tsx` is the interactive SVG
  editor (drag/resize/rotate/marquee-select, snap-to-grid, layers);
  `canvas/StaticPlanRender.tsx` is a non-interactive renderer shared by the
  comparison view and the export pipeline, so exports never visually drift
  from what's on screen.

## Key decisions

- **SVG over canvas/WebGL** for the plan — object counts are in the
  hundreds, not tens of thousands, so DOM-based hit-testing and per-object
  transforms are simpler and fast enough.
- **Rule-based placement, not an optimizer.** The engine is a greedy,
  constraint-scored heuristic — not true bin-packing or ML. It's fast,
  deterministic, and every placement decision traces back to an explicit
  rule, which is what makes the rationale panel possible. It will not always
  find the theoretically optimal layout on a very tightly packed plot.
- **Generator output is axis-aligned** (rotation 0° or 90° only), which
  keeps all the placement/overlap math exact AABB checks, even for
  non-rectangular object types (pool/gazebo ellipses, the L-shaped house) —
  those render as their true shape but are placed/collision-checked against
  their bounding box, the same simplification already used for circular
  wells and water tanks. Manual editing still supports free rotation.
- **Straight-line paths** (gate → house/garage, house → each
  frequently-visited zone) are an explicit MVP simplification, not real
  pathfinding around zone interiors — called out in the PRD as an accepted
  risk.
- **Building-code-style guidance (setbacks, fire/electrical clearances,
  household-area norm) is planning advice, not a compliance guarantee.**
  Distances (3 m house setback, 8 m house-to-outbuilding fire separation,
  250 m²/person, etc.) follow common dacha/allotment practice as a
  reasonable default, not any specific jurisdiction's actual code — flagged
  explicitly in the PRD's non-goals (no permit-grade compliance).
- **Location picker is a country/region dropdown, not an interactive map.**
  A literal clickable world map (e.g. Leaflet + GeoJSON boundaries) would
  need tile/boundary data this app doesn't otherwise depend on, for a UX
  win that a searchable dropdown mostly already delivers; a "Custom / other
  location" option with a manual USD/m² land price covers anywhere not in
  the built-in list. Cost figures (`domain/costData.ts`) are 2025
  market-report ballparks converted to a common USD baseline, not
  appraisals — real prices vary a lot by exact parcel.

## Extension points

- `OBJECT_LIBRARY` (domain/objectLibrary.ts) and `CONSTRAINTS`
  (domain/constraints.ts) are plain data — add a new structure/crop/animal or
  a new adjacency/separation rule without touching the placement algorithm.
- `MODE_WEIGHTS` and `buildProgram`'s per-category scaling
  (engine/placement.ts, engine/sizing.ts) are where a 5th planning mode would
  plug in.
- `textParser.ts`'s bounded vocabulary is the seam for swapping in an
  LLM-assisted extractor later (PRD §9.5, V2 roadmap) without touching
  placement.
- `StyleGuide`/`StylePreset` (domain/types.ts) is defined but only one preset
  ships — a second architectural palette would slot in via
  `CATEGORY_STYLES`.
