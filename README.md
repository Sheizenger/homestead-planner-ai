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
    never drift apart.
  - `exporters.ts` — SVG → PNG/PDF rasterization and JSON serialization.
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
  keeps all the placement/overlap math exact AABB checks. Manual editing
  still supports free rotation.
- **Straight-line access paths** (house → each frequently-visited zone) are
  an explicit MVP simplification, not real pathfinding around zone
  interiors — called out in the PRD as an accepted risk.

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
