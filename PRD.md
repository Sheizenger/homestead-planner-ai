# Homestead Planner AI — Product Requirements Document

**Working title:** Homestead Planner AI
**Status:** Draft v1.0 — implementation-ready
**Owner:** Product/Design/Eng (single-doc spec)

---

## 1. Product Summary

Homestead Planner AI is a desktop-first web application that turns a
combination of natural-language intent and structured project data into an
editable, analyzed, top-down site plan for a rural or semi-rural property.

A user describes what they want (family size, food-production goals,
animals, utilities, aesthetic preferences) in a form and in plain text. The
system generates several distinct, rule-justified layout variants on a
scaled 2D canvas. The user inspects the reasoning behind each zone
placement, compares variants, and then edits the plan directly — moving,
resizing, and reconfiguring objects — while the system continues to flag
area totals, conflicts, and planning risks in real time.

The product is a planning and reasoning tool, not a CAD system and not an
agronomic simulator. It optimizes for **defensible, editable, explainable
layouts**, not photorealistic rendering or engineering-grade precision.

---

## 2. Problem and Users

### 2.1 Problem

Planning a productive homestead plot requires reconciling constraints that
usually live in different people's heads: an architect's sense of
ergonomics, a farmer's sense of sun and soil, a safety inspector's sense of
hazard separation, and a homeowner's sense of what looks good. Existing
tools fail because they specialize in exactly one of these dimensions:

- Generic drawing tools (e.g., diagramming software) have no domain logic —
  the user starts from a blank canvas and must know all the rules already.
- Architectural CAD tools are precise but overkill, slow, and not
  goal-driven — they assume the user already knows the layout.
- Garden-planner apps handle beds and crops but ignore buildings, utilities,
  animals, and whole-plot zoning logic.
- Decorative landscape-design tools optimize for visual mood boards, not
  functional adjacency or safety.

None of them start from "here's what I want my land to do for me" and
produce a defensible starting layout.

### 2.2 Primary Users

- Homeowners planning a rural or semi-rural property from scratch.
- Homesteaders/self-sufficiency households (food, water, energy planning).
- Gardeners and smallholders scaling from a garden to a working plot.
- Owners planning a specific subsystem (orchard, greenhouse, animals,
  solar) inside an existing plot.

### 2.3 Secondary Users

- Landscape designers producing first-pass concepts for clients.
- Permaculture-minded consultants who want a fast, explainable starting
  point they can then hand-refine.

### 2.4 User Goals

- Describe a goal in plain language and get a real starting layout, not a
  blank canvas.
- See *why* a layout is organized the way it is, not just the result.
- Compare alternative organizing strategies before committing.
- Edit confidently, with the tool catching planning mistakes as they go.
- Get a realistic sense of area budgets and tradeoffs (e.g., "more orchard
  means less pasture").

---

## 3. Goals and Non-Goals

### 3.1 Goals

- G1: Convert a mixed structured/free-text brief into 3+ distinct,
  internally consistent layout variants within seconds.
- G2: Make every generated decision explainable in plain language, tied to
  a specific rule (sun, adjacency, separation, access, safety).
- G3: Provide professional, reliable direct-manipulation editing on a
  scaled 2D canvas.
- G4: Surface area accounting and planning-risk warnings continuously, not
  just at generation time.
- G5: Support side-by-side comparison and cross-pollination of variants.
- G6: Ship an experience that reads as serious planning software:
  restrained visual language, dense information, no toy aesthetic.

### 3.2 Non-Goals (explicit)

- Not a 3D rendering or visualization tool.
- Not an agronomic yield simulator (no soil chemistry, no precise crop
  yield modeling).
- Not a GIS/terrain tool (no contour import, no drone/LiDAR ingestion).
- Not a permitting or legal-compliance tool — outputs are planning aids,
  never certified/stamped documents.
- Not a real-time multi-user collaboration tool in MVP.
- Not a contractor marketplace or IoT control system.

---

## 4. Core Workflows

### 4.1 New project → first layouts (primary workflow)

1. User starts a new project, sets plot geometry (size, shape, orientation)
   and coarse context (climate zone, terrain, existing structures).
2. User fills structured goal fields (household size, priorities, animals,
   crops, utilities) and/or writes a free-text brief.
3. User selects a planning mode (Production-Maximizing / Minimum-Maintenance
   / Beauty-Balanced / Safety-First) or leaves the default balanced mode.
4. System generates 3 layout variants. Each renders on the canvas with a
   rationale panel explaining zone placement.
5. User reviews variants in the comparison view, picks one as the active
   working plan (or merges elements from multiple).

### 4.2 Manual refinement

1. User selects an object or zone on the canvas.
2. Right panel shows properties (dimensions, category, metadata) and any
   warnings tied to that object.
3. User drags/resizes/rotates/duplicates/deletes; bottom bar updates
   dimensions and area totals live.
4. Warnings recompute after every edit that could affect them (move,
   resize, delete, add).

### 4.3 Mode switching

User toggles between Schematic / Design / Utilities / Seasonal / Rationale
visualization modes without losing selection or edit state — each mode is a
render/filter layer over the same underlying plan data.

### 4.4 Comparison and merge

User opens variant comparison, views 2–3 variants side by side with
synchronized zoom/pan, and copies individual zones/objects from a
non-active variant into the active one.

### 4.5 Export

User opens export modal, picks PNG / PDF / JSON, configures what's included
(legend, north arrow, warnings overlay, rationale notes), and downloads.

---

## 5. Functional Requirements

### 5.1 Input

- FR-1: System accepts plot dimensions as either a simple rectangle
  (width × depth) or an irregular polygon (vertex list, drawn or entered).
- FR-2: System accepts and displays a north orientation vector, adjustable
  by the user via rotation handle.
- FR-3: System accepts structured fields: household size, region/climate
  zone, slope category (flat/gentle/steep), soil type, water source(s),
  existing buildings (as pre-placed locked objects), grid power
  availability, priority ranking, animals (multi-select with counts),
  crop/planting intentions, infrastructure intentions (solar, well, septic,
  etc.), aesthetic preference slider (utilitarian ↔ ornamental).
- FR-4: System accepts a free-text brief in parallel with structured
  fields; free text is parsed for goal keywords (crops, animals,
  household size, priorities, style words) and merges with — never
  silently overrides — structured fields. Conflicts are surfaced to the
  user, not auto-resolved.

### 5.2 Generation

- FR-5: System produces at least 3 layout variants per generation request,
  each internally labeled with its strategy (compact, production-max,
  beauty-balanced, or the user-selected mode plus two alternates).
- FR-6: Each generated zone/object carries a rationale string referencing
  the specific rule(s) that determined its position.
- FR-7: Generation must complete without blocking the UI; the canvas shows
  a defined loading state per variant.
- FR-8: Generation is deterministic given identical inputs and a fixed
  random seed (for reproducibility and testability), but supports
  re-rolling a variant with a new seed.

### 5.3 Canvas & editing

- FR-9: Canvas renders to real-world scale with a visible scale bar and
  grid; grid spacing is configurable (e.g., 1m/5m/10m).
- FR-10: Every placed object supports move, resize (where applicable),
  rotate, duplicate, delete, and multi-select group transforms.
- FR-11: Snap-to-grid is toggleable; objects also snap to alignment guides
  from nearby object edges/centers.
- FR-12: Layers (by category) can be shown/hidden and locked/unlocked
  independently.
- FR-13: Undo/redo covers all edit operations, scoped per project (not per
  variant — switching variants does not corrupt history, each variant
  keeps its own history stack).
- FR-14: Existing/locked structures (marked as "as-built") are visually
  distinct and cannot be moved unless explicitly unlocked by the user.
- FR-15: Zones may be rectangular or polygonal; polygon vertices are
  individually editable.

### 5.4 Analytics

- FR-16: System computes and displays: total plot area, per-zone area,
  per-category area and percentage of plot, and a running "unallocated
  land" figure.
- FR-17: System recomputes warnings after every structural edit
  (add/move/resize/delete), not only at generation time.
- FR-18: Warnings carry a severity (info/caution/critical), a plain-language
  message, the offending object(s), and — where feasible — a one-click
  suggested fix (e.g., "increase separation" nudges an object).

### 5.5 Variants & comparison

- FR-19: User can view 2 or 3 variants side by side with independent pan
  but synchronized zoom.
- FR-20: User can copy a single zone/object from a non-active variant into
  the active variant, with automatic collision detection against existing
  objects.

### 5.6 Export

- FR-21: PNG export rasterizes the current canvas view at a
  print-reasonable resolution, honoring the current visualization mode.
- FR-22: PDF export produces a single-page (or paginated, for large plots)
  document containing the plan, legend, scale, north arrow, and optional
  rationale/warnings appendix.
- FR-23: JSON export serializes the full project (all variants, all
  objects, metadata, warnings) in a documented schema that can be
  re-imported losslessly.

---

## 6. Non-Functional Requirements

- NFR-1: Desktop-first responsive layout; usable down to a 1280px viewport,
  degrades gracefully (panels collapse to drawers) below that — full
  editing fidelity is not guaranteed on phone-sized screens.
- NFR-2: Canvas interaction (drag/resize/rotate) must stay responsive
  (target ≥50fps perceived smoothness) with plans containing up to ~300
  objects.
- NFR-3: Generation of 3 variants for a typical plot (≤2 hectares, ≤150
  objects per variant) completes in well under a second of compute (this
  is a rule-based/heuristic engine, not a network-bound LLM call, though an
  LLM may be used only for free-text parsing/explanation phrasing — see
  §9.5).
- NFR-4: Visual design uses a restrained, architectural/landscape-plan
  visual language: muted zone-category palette, consistent line weights,
  legible labels at multiple zoom levels — not a generic "AI product"
  gradient-heavy look.
- NFR-5: All destructive actions (delete object, delete variant, overwrite
  project) require confirmation or are undoable.
- NFR-6: Clear, persistent visual distinction between AI-generated/uneditable-by-default
  recommendation elements (until accepted) and confirmed user-owned plan
  objects.
- NFR-7: Project state persists locally (browser storage) between sessions
  without explicit save, plus explicit export/import for portability.

---

## 7. Information Architecture

### 7.1 Key Screens

#### Onboarding / New Project
- **Purpose:** Capture enough structured + free-text input to run a first
  generation; offer a fast path via sample projects.
- **Main components:** Plot geometry input (shape picker + dimension
  fields or polygon draw), context fields (climate/terrain/soil/water/power),
  goals form (household, animals, crops, infrastructure, priorities,
  aesthetic slider), free-text brief textarea, planning-mode selector,
  "Generate" CTA, "Start from sample project" list.
- **User actions:** fill form, paste/write brief, pick mode, generate,
  or load a sample and skip straight to the workspace.
- **Data shown:** live-computed plot area from entered dimensions;
  validation state per field.
- **Edge cases:** irregular polygon self-intersects (block generation,
  show inline error); free text contradicts structured fields (flag,
  don't silently override); extremely small plot where requested
  program can't fit (generate anyway, surface a critical "over capacity"
  warning rather than refusing).

#### Main Planner Workspace
- **Purpose:** The primary editing surface — generation review + manual
  refinement in one place.
- **Main components:** Left panel (brief/inputs, collapsible after
  generation), center canvas, right panel (selection properties +
  warnings feed), top toolbar (mode switch, layer toggles, variant
  switcher, zoom, export entry), bottom status bar (cursor coordinates,
  selection dimensions, total/used/unallocated area, active
  grid/snap state).
- **User actions:** select/edit objects, switch visualization mode, switch
  active variant, toggle layers, open comparison, open export.
- **Data shown:** current variant's full plan, live analytics, live
  warnings.
- **Edge cases:** selection spans locked and unlocked objects (group
  transform applies only to unlocked members, locked members shown
  with a lock badge); object resized below its minimum functional size
  (block or warn, e.g., a goat paddock can't shrink below a
  containment-area minimum without a critical warning).

#### Variant Comparison View
- **Purpose:** Evaluate tradeoffs across generated variants before
  committing.
- **Main components:** 2–3 synchronized canvases, per-variant summary
  card (strategy label, key area stats, top 3 rationale highlights,
  top warnings), "copy object to active" affordance, "make active"
  button.
- **User actions:** pan each canvas independently, zoom all together,
  drag-copy a zone from one variant into the active one, promote a
  variant to active.
- **Data shown:** per-variant analytics snapshot, diff highlights
  (e.g., "+120 m² orchard vs. compact variant").
- **Edge cases:** copying an object that collides with the active
  variant's existing layout (show collision, offer auto-nudge or
  cancel).

#### Export Modal
- **Purpose:** Produce shareable/archival output.
- **Main components:** format tabs (PNG/PDF/JSON), mode-to-export
  picker, include-toggles (legend, rationale appendix, warnings
  appendix, north arrow/scale), resolution/paper-size options,
  preview thumbnail.
- **User actions:** configure, preview, download.
- **Data shown:** live preview reflecting current toggle state.
- **Edge cases:** exporting a plan with unresolved critical warnings
  (allowed, but the export includes a visible "unresolved warnings"
  disclaimer banner).

#### Analytics Panel (docked, not just modal)
- **Purpose:** Always-available quantitative read on the plan.
- **Main components:** stacked area breakdown by category, utilization
  ratio, food-production allocation estimate, warning list grouped by
  severity.
- **User actions:** click a warning to select/focus its object(s); click
  a category to isolate that layer.
- **Data shown:** `AnalyticsSnapshot` for the active variant, recomputed
  on edit.
- **Edge cases:** zero objects placed yet (show empty state with
  guidance, not a blank chart).

#### Object Detail Editor
- **Purpose:** Precise, form-based editing of a single selected object as
  an alternative to freehand drag.
- **Main components:** name/label field, category (read-only, set at
  creation), numeric x/y/width/height/rotation fields, metadata fields
  relevant to category (e.g., animal count + type for a paddock, panel
  wattage for solar), lock toggle, delete button, attached warnings list.
- **User actions:** edit precise values, lock/unlock, delete, jump to
  a related object (e.g., "view paired utility node").
- **Data shown:** the object's full metadata and any constraints/warnings
  referencing it.
- **Edge cases:** manual numeric entry that would overlap another
  locked object (warn, allow override since user is in control per
  Core Principle 4).

---

## 8. Data Model

Entities (TypeScript-flavored, implementation-ready):

```
Project
  id, name, createdAt, updatedAt
  brief: { structuredInputs: StructuredInputs, freeText: string }
  plot: Plot
  variants: LayoutVariant[]
  activeVariantId
  stylePreset: StylePresetId

Plot
  id
  boundary: Point[]          // polygon, rectangle is a 4-point special case
  northAngleDeg: number
  climateZone, terrainSlope, soilType, waterSources[], gridPower: boolean
  existingObjects: PlanObject[]   // pre-placed, locked by default

Zone
  id, variantId, category: ZoneCategory
  boundary: Point[]           // polygon or rect
  label, colorOverride?
  metadata: Record<string, unknown>
  locked: boolean

PlanObject
  id, variantId, zoneId?
  type: ObjectTypeId          // references Object Library catalog entry
  category: ObjectCategory
  transform: { x, y, width, height, rotationDeg }
  label, locked, layerId
  metadata: Record<string, unknown>   // e.g. { animalCount, cropType, kWp }
  rationale?: string          // why the generator placed it here

Path
  id, variantId, points: Point[], widthM, surfaceType, category: 'access'|'service'

Fence
  id, variantId, points: Point[], fenceType, gated: boolean

UtilityNode
  id, variantId, type: 'well'|'septic'|'power'|'water-tank'|'solar'|...
  position: Point, connections: UtilityNodeId[]

LayoutVariant
  id, projectId, strategyLabel, seed
  zones: Zone[], objects: PlanObject[], paths: Path[], fences: Fence[], utilityNodes: UtilityNode[]
  history: EditHistoryStack   // undo/redo, scoped to this variant
  analytics: AnalyticsSnapshot
  warnings: Warning[]
  rationaleSummary: string[]

Constraint
  id, kind: 'adjacency'|'separation'|'sunlight'|'access'|'safety'
  subjectType, relatedType, rule (min/max distance, required orientation, etc.)

Warning
  id, severity: 'info'|'caution'|'critical'
  message, ruleId (Constraint.id), objectIds[]
  suggestedFix?: { label, action }

AnalyticsSnapshot
  totalAreaM2, allocatedAreaM2, unallocatedAreaM2
  byCategory: { category, areaM2, percent }[]
  estimatedFoodProductionScore
  maintenanceComplexityScore
  computedAt

StylePreset
  id, name, paletteMap: Record<ZoneCategory, colorToken>, lineWeightScale
```

---

## 9. Autoplanning Logic

### 9.1 Inputs to the planner

- Plot polygon + north vector + slope + climate zone.
- Household size and priority ranking (production vs. maintenance vs.
  beauty vs. safety).
- Requested program: animals (type + count), crops/plantings, structures,
  utilities.
- Free-text-derived signals: extracted keywords mapped to the same program
  vocabulary as structured inputs (see §9.5).

### 9.2 Placement algorithm (heuristic, not ML)

1. **Program sizing** — translate requested items into area/footprint
   budgets using a lookup table (e.g., "goats ×4" → paddock ≥ 200 m² +
   shelter ≥ 8 m²; "family of 3, potatoes" → ~120–180 m² potato bed).
2. **Zone graph construction** — build a weighted adjacency graph:
   nodes = requested zone types, edges = desired proximity/separation
   scores derived from `Constraint` rules (e.g., kitchen-garden ↔ house:
   high proximity; animal paddock ↔ house: moderate distance; septic ↔
   well: hard minimum separation).
3. **Anchor placement** — place the house (or dominant existing
   structure) first, oriented for sun/access; this anchors the graph.
4. **Greedy constrained placement** — place remaining zones in priority
   order (structures → utilities → high-adjacency food zones → animals →
   perennials → future-expansion reserve), scoring candidate positions on
   the plot grid by: sunlight fit, adjacency satisfaction, separation
   violations (hard fail below minimum), access-path length, and (in
   beauty mode) proportion/alignment to existing zones.
5. **Path & fence synthesis** — generate access paths connecting entries
   to placed zones by shortest reasonable route avoiding zone interiors;
   synthesize perimeter/paddock fencing where category requires
   containment.
6. **Variant differentiation** — run the same graph through 3 scoring
   weight profiles (compact/efficient minimizes path length and total
   footprint; production-maximizing weights food-producing area highest;
   beauty-balanced weights proportion/symmetry/sightlines alongside
   function) to produce meaningfully different, not cosmetically
   shuffled, layouts.
7. **Rationale generation** — for each placed zone, record which scoring
   terms dominated its final position, and phrase this as the
   `rationale` string.

### 9.3 Rule categories the engine must encode

- Sunlight/shade: south-facing (or hemisphere-correct) exposure preferred
  for food production and solar; tall structures/trees checked against a
  simple shadow-cast heuristic (angle × height) relative to sun-sensitive
  zones.
- Access/ergonomics: frequently-visited zones (kitchen garden, hen house)
  closer to the house than infrequently-visited ones (orchard, back
  pasture); path length is scored, not just presence/absence.
- Noise/privacy: quiet zones (reading patio, bedroom-facing yard) kept
  apart from generators, workshops, animal shelters.
- Odor/sanitation: animal zones and compost kept downwind-biased and
  distanced from house entries and food-prep zones; septic kept a hard
  minimum distance from wells.
- Clean/dirty flow: service paths for animals/utilities kept separate
  from guest/leisure paths where plot size allows.
- Utility adjacency: solar near battery/inverter near house load center;
  well near pump near water-tank near irrigation-heavy zones.
- Safety: fencing required around animal zones and water tanks/ponds;
  minimum clearance around generators/fuel storage.
- Future expansion: a reserved, explicitly labeled unallocated zone sized
  proportionally to plot size in non-compact modes.

### 9.4 Modes

| Mode | Weighting emphasis |
|---|---|
| Maximum Productivity | Food-producing area, sunlight fit |
| Minimum Maintenance | Path length, zone count/complexity, low-touch perennials over annual beds |
| Beauty + Function Balance | Proportion/symmetry alongside function terms |
| Safety First | Separation/containment/access-for-emergency terms weighted highest, sometimes at the cost of compactness |

### 9.5 Free-text handling

- Free text is parsed for a bounded vocabulary (crops, animals, structures,
  household size, style adjectives, priority words) rather than treated as
  an open-ended prompt to an opaque model — this keeps generation
  deterministic and explainable per Core Principle 4 ("AI should propose;
  user should remain in control").
- An LLM call *may* be used strictly for (a) extracting structured signals
  from free text into the bounded vocabulary, and (b) phrasing rationale
  strings in natural language from the structured scoring terms the
  heuristic engine already computed. The LLM never decides placement
  itself — placement stays inspectable and reproducible.
- Unrecognized free-text terms are not silently dropped: they appear in a
  "not yet understood" list so the user knows the brief wasn't fully used.

---

## 10. UX / UI Requirements

- Layout: left panel (brief/inputs, collapsible) — center canvas — right
  panel (properties/warnings) — top toolbar — bottom status bar, per the
  primary UX model.
- Visual language: architectural/landscape-plan aesthetic — muted,
  distinguishable zone-category palette; consistent stroke weights per
  object category; labels legible at 3+ zoom levels; no drop-shadow-heavy
  or gradient-heavy "AI app" styling.
- Modes are view filters over one data model: Schematic (line/fill only),
  Design (fuller rendering with texture/planting icons), Utilities
  (highlight utility nodes/connections, mute everything else), Seasonal
  (toggle deciduous shade states, dormant vs. active beds), Rationale
  (overlay callouts tied to each zone's rationale string).
- North arrow and scale bar always visible on canvas, in every mode and
  every export.
- Distinct, persistent visual treatment for: locked/as-built objects,
  AI-generated-not-yet-accepted elements (if a "propose then accept" step
  is used), user-owned confirmed objects, and objects with active
  warnings (badge/outline).
- Dark mode and light mode, both meeting WCAG AA contrast for zone
  category colors and warning severities.
- Keyboard support: delete/backspace to delete selection, arrow keys to
  nudge (grid-stepped), ctrl/cmd+Z / shift+ctrl/cmd+Z for undo/redo,
  ctrl/cmd+D duplicate.

---

## 11. MVP Scope

**In:**
- Project setup screen (structured inputs + free-text brief + sample
  projects).
- Editable 2D canvas (SVG) with move/resize/rotate/duplicate/delete,
  snap-to-grid, layer show/hide, undo/redo.
- At least 3 rule-based autoplanning variants with rationale text.
- Object library covering all categories listed in §"Smart Object
  Library" (representative set per category, not exhaustive skinning).
- Area analytics (per-zone, per-category, utilization).
- Conflict/warning detection (separation, containment minimums, capacity
  overflow).
- Export: PNG, PDF, JSON.
- At least one fully realistic preloaded sample project.

**Out (explicit non-goals for MVP, revisit in V2/V3):**
- Full 3D rendering.
- Precise agronomic simulation (yield/soil chemistry).
- GIS-grade terrain/contour modeling.
- Permit-grade legal compliance guarantees.
- Multiplayer real-time collaboration.
- Contractor marketplace.
- IoT integration.
- Exhaustive engineering-grade utility sizing calculations.

---

## 12. Success Criteria

The product succeeds if a user can, without external help:

1. Enter a realistic property brief (structured + free text) in under 5
   minutes.
2. Receive 3 layout variants they perceive as genuinely different
   strategies, not cosmetic reshuffles.
3. Read the rationale for at least the house, one food zone, and the
   animal zone (if present) and find it plausible.
4. Make at least one manual edit (move/resize an object) with confidence
   that area totals and warnings stay accurate.
5. Identify at least one planning mistake (e.g., septic-well distance,
   over-allocated area) via the warnings system before "building" anything.
6. Export a plan they'd be willing to show to a spouse/contractor/consultant.

---

## 13. Risks and Tradeoffs

- **Heuristic engine plausibility risk:** a rule-based system can produce
  layouts that are technically constraint-satisfying but "feel" arbitrary.
  Mitigation: invest disproportionately in the rationale/explanation layer
  so even an imperfect layout is legible and correctable — Core Principle
  4 makes the user the backstop, not the algorithm.
- **Free-text ambiguity:** natural language goals are often
  underspecified ("ergonomic," "beautiful"). Mitigation: bounded-vocabulary
  extraction (§9.5) plus an explicit "not yet understood" surface rather
  than silent guessing.
- **Scope creep toward simulation:** stakeholders will keep asking for
  "more accurate" yield/shadow/engineering math. Mitigation: the
  non-goals in §3.2/§11 are load-bearing; each request should be
  evaluated against "does this serve legible planning, or does it turn
  this into a simulator we can't validate."
- **Canvas performance vs. fidelity:** rich SVG rendering (icons, textures)
  at high object counts can degrade interaction smoothness. Mitigation:
  schematic mode as the default/fallback rendering path; design-mode
  detail only rendered above a zoom threshold.
- **Irregular plots break grid heuristics:** rectangular-grid placement
  logic doesn't trivially generalize to arbitrary polygons. Mitigation:
  bound the placement search to the plot's bounding box intersected with
  the polygon, and accept lower placement quality on highly irregular
  shapes rather than failing generation.
- **"3 variants" becoming 3 near-duplicates:** without deliberate scoring
  weight divergence, generated variants regress to the mean. Mitigation:
  variant differentiation is a first-class algorithm requirement (§9.2
  step 6), tested with explicit "variants must differ by ≥X% in category
  area allocation" acceptance criteria.
- **Trust calibration:** if warnings are too noisy, users ignore them; if
  too sparse, users miss real problems. Mitigation: severity tiers and a
  short, curated initial rule set rather than maximal rule coverage at
  launch.

---

## 14. Engineering Handoff Notes

- Treat `LayoutVariant` as the unit of undo/redo and of comparison — never
  mutate a variant's arrays in place; use immutable updates so history
  snapshots are cheap and comparison views can hold multiple variants in
  memory concurrently.
- Keep the placement/scoring engine (§9) as pure functions
  (inputs → scored candidate layout) so it is unit-testable independent of
  rendering, and so "re-roll with new seed" is just a re-invocation.
- The rationale strings must be generated from the same scoring terms the
  engine used for placement — do not let an LLM free-associate
  explanations disconnected from the actual placement math; this is a
  correctness requirement, not a style preference.
- Warnings recomputation must be triggered from a single canonical
  "plan changed" event, not scattered per-interaction — otherwise stale
  warnings will drift from canvas state under rapid editing.
- Object library entries should be data (a catalog), not per-type React
  components duplicating rendering logic — a generic renderer keyed by
  category/shape keeps future object additions cheap.
- Export code paths (PNG/PDF) should render from the same SVG scene graph
  the canvas uses, not a parallel export-only renderer, to avoid visual
  drift between what the user edits and what they export.

---

## A. Prioritized Feature Roadmap

**MVP (V1):**
- Project setup, structured + free-text input.
- Rule-based 3-variant generation with rationale.
- Editable SVG canvas: full manipulation set, snap, layers, undo/redo.
- Object library (representative catalog).
- Analytics + warnings.
- Variant comparison (view + copy-object).
- Export: PNG/PDF/JSON.
- One seeded realistic sample project.
- Dark/light mode.

**V2:**
- Seasonal mode with deciduous shade-state toggling and dormant-bed
  states.
- Expanded object library depth (more crop/animal/utility subtypes).
- LLM-assisted free-text extraction and rationale phrasing (replacing the
  MVP's simpler keyword matcher) per §9.5.
- Shareable read-only plan links (no auth/collab editing yet).
- Basic terrain slope visualization (hillshade-style overlay from a
  user-entered slope direction/grade, not real GIS data).
- Cost/budget estimation overlay (rough material/area-based cost bands).

**V3:**
- Multi-user collaboration (shared editing, comments/annotations).
- Import of real terrain data (contour/DEM) for slope-aware placement.
- Expanded regional climate rule packs (frost dates, hardiness-zone-aware
  crop suggestions).
- Contractor/consultant handoff exports (structured BOM-style zone/object
  manifest).
- Plugin-style constraint packs (e.g., regional building-code hint sets,
  clearly labeled as advisory, not compliance guarantees).

---

## B. Recommended Technical Stack

- **Frontend framework:** React + TypeScript (Vite build).
- **State management:** Zustand (lightweight, good fit for
  undo/redo-scoped-per-variant history without Redux boilerplate).
- **Canvas rendering:** SVG (not `<canvas>`/WebGL) — object counts in
  scope (~hundreds, not tens of thousands) favor SVG's DOM-based
  hit-testing, accessibility hooks, and simpler per-object transform
  editing; revisit only if profiling shows real degradation at target
  scale.
- **Styling:** Tailwind CSS with a small custom design-token layer for
  the zone-category palette and light/dark themes.
- **PDF export:** jsPDF (or pdf-lib) driven from the same SVG scene via
  serialization, not a second rendering path.
- **PNG export:** SVG → canvas rasterization (e.g., via a canvas
  `drawImage` of a serialized SVG blob) at the current viewport.
- **Persistence:** browser `localStorage`/`IndexedDB` for autosave;
  explicit JSON export/import for portability; no backend required for
  MVP (a thin backend can be added in V2+ for share links/auth).
- **Testing:** Vitest for the placement/scoring engine (pure-function
  unit tests) and analytics/warnings logic; React Testing Library for
  panel/canvas interaction smoke tests.

---

## C. Handoff Prompt for Claude Code (MVP Implementation)

> Build the MVP of Homestead Planner AI as a React + TypeScript + Vite
> web app using SVG for the editable 2D site-plan canvas and Zustand for
> state. Implement the domain model in §8 (Project, Plot, Zone,
> PlanObject, Path, Fence, UtilityNode, LayoutVariant, Constraint,
> Warning, AnalyticsSnapshot, StylePreset) as the single source of truth.
> Build the rule-based placement/scoring engine described in §9 as pure,
> unit-testable functions that take a Project's brief + Plot and a
> weighting profile (one of the 4 modes in §9.4) and return a
> LayoutVariant with per-object rationale strings sourced from the same
> scoring terms used for placement. Generate 3 variants per request that
> are measurably different in category-area allocation, not cosmetic
> reshuffles. Build the workspace UI per the layout in §7.1 (Main Planner
> Workspace) and §10: left brief/input panel, center canvas with
> drag/resize/rotate/duplicate/delete/snap/layers/undo-redo, right
> properties/warnings panel, top toolbar (mode switch, layers, variant
> switcher, zoom, export), bottom status bar (dimensions/areas/warnings).
> Implement the analytics + warnings engine from §5.4/§9.3 and the
> variant comparison view from §7.1. Implement export to PNG, PDF, and a
> documented JSON schema, rendered from the same SVG scene graph the
> canvas uses. Ship one fully realistic preloaded sample project. Respect
> the MVP scope boundaries in §11 — do not build 3D rendering, agronomic
> simulation, GIS terrain import, or multiplayer collaboration. Favor a
> restrained, architectural/landscape-plan visual style over generic
> "AI product" gradients, with working dark and light themes.
