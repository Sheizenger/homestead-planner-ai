# Backlog

Everything known and not yet done. `AGENTS.md` holds the decisions that
govern how these are built.

## Port stages

In order — each stage assumes the previous one landed.

1. ~~**Fixtures.**~~ Done. 48 in `fixtures/`, six scenarios across four modes
   and two seeds, plus `rng.json` and `objectLibrary.json`. `npm run fixtures`
   regenerates; CI fails if the result differs from what is committed.
2. ~~**Domain and geometry.**~~ Done. Types, `mulberry32`, `jsRound`,
   polygons, transforms, plot shapes and the object catalog, each pinned
   against the reference data.
3. ~~**Planner.**~~ Done, folding in stage 4's `analytics`/`warnings`/
   `constraints`/`elevation`/`waterfront` early since `Generate.variant`
   needed them to produce a complete `Layout`. `costs` and `materials` remain
   — UI-only, not part of the generated plan, deferred to whichever later
   stage first needs them. `GenerateTests` runs the whole pipeline (text
   parsing → sizing → placement → paths/fences → utility hookups →
   future-expansion reserve → analytics → warnings, unplaced items included)
   against all 48 fixtures field by field; passed on the first full run.

   Three precision traps surfaced along the way, each caught by a fixture
   comparison rather than reasoning about the code:
   - **Unstable sort.** The tier/area placement sort and the
     future-expansion corner-distance sort both tie constantly (same-type
     crops share a tier and an area; corner distance repeats across a
     symmetric grid). Swift's `sort` isn't stable, so both carry an explicit
     original-index tie-break.
   - **`Rect` as origin+size.** `maxY` derived as `minY + height` is not
     bit-identical to TypeScript's independently computed `y + h/2` —
     floating-point addition isn't associative. Broke `PathsAndFences`
     (exact-equality point comparisons) while leaving `Placement` untouched
     (its decisions are threshold comparisons a ULP doesn't flip). `Rect` now
     stores all four edges directly; see its doc comment.
   - **`toFixed`/`toLocaleString`.** JavaScript's `toFixed` rounds against a
     double's *exact* value, not its shortest round-trip decimal string —
     `1.45` prints as `"1.45"` in both languages but `.toFixed(1)` gives
     `"1.4"`, because the underlying double is a hair under 1.45. Ported via
     a high-precision decimal expansion rather than a scaled-Double round,
     which reintroduces its own binary rounding before the intended one.

   `suggestedFix` is still only *carried* on warnings, exactly as the web app
   does — not wired to an action. That, plus the AABB-only overlap check,
   are the two fixes stage 4 originally scoped; both are UI/interaction work
   that belongs with the canvas (stage 6) and panels (stage 7), not the
   engine, so they moved there rather than being done twice.
5. **App shell.** `PlanDocument`/`Variant`/`ProjectModel` are done in
   `HomesteadCore`, tested on Linux (84 tests): accumulation, staleness
   detection, object editing, a readable JSON codec with `schemaVersion`.
   `UndoManager` doesn't exist outside Apple platforms, so it isn't — and
   can't be — part of this; see AGENTS.md's "Settled decisions". What
   remains, and needs a Mac:
   - The Xcode project itself. Nothing has been created yet — SPM can't
     produce a `.app` bundle, entitlements, or an Info.plist, and generating
     an `.xcodeproj` by hand is fragile. This is the one-time action AGENTS.md
     flags as needing the user: create an empty macOS App target in Xcode and
     add `swift/` as a local package dependency.
   - `FileDocument`/`ReferenceFileDocument` conformance wrapping
     `PlanDocument` — lives in the app target, not `Core`, since the protocol
     itself is a SwiftUI import.
   - Wiring `NSUndoManager`/`UndoManager.registerUndo` around each
     `ProjectModel` mutator from the view layer that owns the document.
   - The CI macOS job: builds the app target, runs any App-layer tests, and
     produces the screenshot contact sheet. Waits on the Xcode project
     existing.
6. **Canvas.** `Viewport` over `Canvas`: cursor-anchored zoom, pan,
   fit-to-plot, zoom-to-selection, screen-space north arrow and scale bar.
   Hit-testing is manual.
7. **Panels.** Brief, object properties, warnings, variant list with rename /
   delete / badges, object palette (search over the catalog, `+` and a
   keyboard shortcut), and the "brief changed since this variant was
   generated" banner with its generate-alongside action.
8. **Export, locales, accessibility.** PNG and PDF from the same scene the
   canvas draws; `en` + `ru` with a key-parity test; `Canvas` is opaque to
   VoiceOver, so the plan needs a parallel accessible representation.

## Deferred

- iPad: separate input model, separate panel layout.
- Object palette with drag-and-drop onto the canvas. The search palette from
  stage 7 covers the need; dragging adds a whole layer.
- Variant thumbnails in the variant list — a second render path.
- Free-text brief parsing and rationale phrasing via an LLM (`PRD.md` §9.5
  still describes this as V2).

## `PRD.md` amendments

The spec has drifted from the product and needs a pass:

- §3.2 and §11 list terrain/contour modelling and cost estimation as
  non-goals. Both shipped in the web app, and both are in scope for the port.
  Image-trace boundary import is likewise built and unlisted.
- §B names the web stack as the recommended one. It describes the frozen
  implementation, not the target.
- §5.4 FR-17 (recompute on every structural edit) and §14 (a single
  canonical "plan changed" event) describe what the derived-state decision
  actually delivers; the web implementation never met them.

## Frozen web app

Found during the audit, catalogued so the port does not repeat them. Not
being fixed in `src/`.

**Data integrity**

- `generate()` (`state/projectStore.ts:358`) replaces every variant. Undo
  cannot recover the loss — history lives inside the discarded variants — and
  the 600 ms autosave overwrites the stored copy immediately. Same for
  `regenerateVariant`.
- Analytics and warnings recompute only from object mutators, so changing the
  brief, the plot size, or the boundary leaves stale numbers and stale
  warnings on screen.
- `persistence.ts:26` serialises every variant's 40-deep history into
  `localStorage`, and swallows the quota error, so autosave dies silently.

**Geometry the port deliberately diverges from**

Both are wrong in `src/`, both are reachable from the UI, and neither is
covered by a test — which is how they survived. The Swift implementations are
correct and say so at the call site; fixtures avoid the affected inputs so the
divergence cannot mask a genuine porting error.

- `buildLShapeBoundary` (`engine/plotShapes.ts:30`) builds the `sw` case as a
  `notchWidth × (height - notchHeight)` bite out of the *north*-west. A 60×45
  plot with a 20×15 notch comes out at 2100 m² instead of 2400, with the
  missing corner on the wrong side. The other three corners are right.
- `resizeFromCorner` (`engine/geometry.ts:195`) offsets the new centre by
  `-cornerSign`, walking away from the corner being dragged. Dragging the
  bottom-right of an 8×4 at (10,10) out to (20,16) lands the rect at corners
  (-8,0)…(6,8): it flies up and left, and the corner meant to stay pinned
  becomes the opposite one. Every resize in the web app does this.

**Missing and dead**

- No way to add an object: the store has `duplicateObjects` and no
  `addObject`, and `OBJECT_LIBRARY` is never presented as a catalog.
  `parseEditCommand` (`engine/editCommands.ts:62`) builds its vocabulary from
  types already placed, so the quick-edit route is closed too.
- `layerLocked` is toggled and never read — the layer lock button does
  nothing.
- `suggestedFix` is computed for every warning and rendered nowhere, so
  FR-18's one-click fix does not exist.
- Deleting a locked object clears the selection and does nothing else, with
  no feedback (`projectStore.ts:416`).
- `copyObjectToActive` returns silently on collision (`:501`) instead of
  showing it and offering a nudge.
- Overlap warnings compare AABBs of rotated objects, reporting overlaps that
  are not there.

**Interaction and presentation**

- Zoom scales the SVG's `width`/`height` inside an `overflow-auto` div: it
  anchors top-left, and there is no wheel zoom, drag pan, fit-to-screen, or
  zoom-to-selection.
- North arrow and scale bar are drawn in world coordinates and scroll off
  screen, against §10.
- Panels are a fixed 288 px, neither collapsible nor resizable; §7.1 promised
  a collapsible left panel.
- Theme is not persisted (locale is), and the selected planning mode is local
  component state, lost on reload and absent from the toolbar.
- After "new project" there are no variants: the canvas reads "no layout" and
  the only Generate button sits at the bottom of a long scrolling panel.
- Undo/redo are never disabled, and no shortcut help exists.
- Rationale mode draws 0.55 m text truncated at 57 characters with no
  collision avoidance.
- Marquee selection tests object centres and catches objects on hidden
  layers.
- SVG objects are neither focusable nor labelled, and active states are
  carried by colour alone.
- Quick-edit commands match English labels only, in a UI translated into five
  languages.
