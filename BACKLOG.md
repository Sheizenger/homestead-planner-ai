# Backlog

Everything known and not yet done. `AGENTS.md` holds the decisions that
govern how these are built.

## Port stages

In order — each stage assumes the previous one landed.

1. **Fixtures.** Node script over the TypeScript engine: matrix of plot
   shapes (rect, L-shape, waterfront, sloped, undersized), all four planning
   modes, several seeds. Dumps objects with transforms, paths, fences,
   utility nodes, warnings, and analytics to `fixtures/`. Regenerated in CI
   so drift between the two engines shows up as a failing job.
2. **Domain and geometry.** Swift types, `geometry`, `plotShapes`. Existing
   `*.test.ts` cases port to swift-testing alongside. `mulberry32` and the
   `jsRound` half-breaking rule are done and pinned against the fixtures.
3. **Planner.** `sizing`, `placement`, `pathsAndFences`, `generate`. Done
   when every fixture matches.
4. **Rules and analytics.** `analytics`, `warnings`, `constraints`, `costs`,
   `materials`, `elevation`, `waterfront`. Built with the fixes below folded
   in rather than ported and corrected afterwards:
   - `suggestedFix` performs a deterministic nudge to the minimum distance,
     refusing when it would leave the plot or create a new violation, and
     routing through `UndoManager`.
   - Overlap detection uses an AABB prefilter with an exact rotated-rectangle
     test behind it, so rotated objects stop reporting phantom overlaps.
5. **App shell.** Document model, `@Observable` state, variants that
   accumulate, `UndoManager`. First thing the user builds in Xcode.
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
