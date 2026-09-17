//
//  PlanCanvasView.swift
//  Homestead
//
//  The whole scene in one Canvas call, per AGENTS.md's settled decision
//  against drawing ~300 individual views. World coordinates (Double, metres)
//  go through HomesteadCore's Viewport — the real pan/zoom the web app never
//  had — and are converted to CGFloat explicitly, since Swift won't do that
//  implicitly. No axis flip: the engine's +Y-is-south convention already
//  matches SwiftUI's downward-growing Y.
//
//  Colours come from CategoryStyle, which is the web app's palette including
//  its dark variants. North arrow, scale bar and legend are screen-space
//  furniture, deliberately outside the viewport transform, so they stay put
//  and stay legible at any zoom (see Viewport's own doc comment).
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct PlanCanvasView: View {
    let plot: Plot
    let variant: Variant
    @Binding var viewport: Viewport
    @Binding var selectedObjectID: String?
    /// The objects a selected warning is about — drawn with a warning-coloured
    /// halo so "these two are too close together" points at a pair on the plan
    /// rather than at two labels in a list.
    var highlightedObjectIDs: Set<String> = []
    var showsDimensions: Bool
    /// Called with a world-space delta while an object is being dragged, and
    /// once more with `committed: true` when the drag ends — so the owner can
    /// wrap the whole gesture in a single undo step rather than one per frame.
    var moveObject: (String, Point, Bool) -> Void = { _, _, _ in }

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragAnchor: CGSize = .zero
    @State private var magnifyAnchor: CGFloat = 1
    @State private var draggingObjectID: String?
    @State private var dragResolved = false
    @State private var legendExpanded = true

    private var chrome: CanvasChrome { CanvasChrome.of(colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGrid(context, size: size)
                drawPlot(context)
                drawWaterfront(context)
                drawZones(context)
                drawFences(context)
                drawPaths(context)
                drawObjects(context)
                drawScaleBar(context, size: size)
                drawNorthArrow(context, size: size)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) { legend }
            .overlay(alignment: .bottomTrailing) { zoomControls(in: geometry.size) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - dragAnchor.width,
                            height: value.translation.height - dragAnchor.height
                        )
                        dragAnchor = value.translation

                        // What this gesture is gets decided once, from where it
                        // began: on an object it moves that object, on empty
                        // ground it pans the view. Resolved by an explicit
                        // flag rather than "is the translation still zero",
                        // since the first event isn't guaranteed to be.
                        if !dragResolved {
                            dragResolved = true
                            let start = viewport.toWorld(Point(x: Double(value.startLocation.x), y: Double(value.startLocation.y)))
                            draggingObjectID = HitTesting.hitTest(start, in: variant.objects)
                        }

                        if let id = draggingObjectID {
                            moveObject(id, Point(x: Double(delta.width) / viewport.scale, y: Double(delta.height) / viewport.scale), false)
                        } else {
                            viewport.pan(byScreen: Point(x: Double(delta.width), y: Double(delta.height)))
                        }
                    }
                    .onEnded { value in
                        dragAnchor = .zero
                        dragResolved = false
                        let moved = abs(value.translation.width) + abs(value.translation.height)
                        if let id = draggingObjectID {
                            draggingObjectID = nil
                            if moved < 4 {
                                selectedObjectID = id
                            } else {
                                moveObject(id, Point(x: 0, y: 0), true)
                            }
                            return
                        }
                        guard moved < 4 else { return }
                        let world = viewport.toWorld(Point(x: Double(value.location.x), y: Double(value.location.y)))
                        selectedObjectID = HitTesting.hitTest(world, in: variant.objects)
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let factor = value.magnification / magnifyAnchor
                        magnifyAnchor = value.magnification
                        let centre = Point(x: Double(geometry.size.width) / 2, y: Double(geometry.size.height) / 2)
                        viewport.zoom(by: Double(factor), anchor: centre)
                    }
                    .onEnded { _ in magnifyAnchor = 1 }
            )
            // Re-fit on every layout event, not just the first. Fitting once
            // in onAppear is what drew the plan as a postage stamp in the
            // corner: the first layout pass reports a much smaller canvas
            // than the settled window, and nothing ever corrected it.
            .onAppear { fitToPlot(in: geometry.size) }
            .onChange(of: geometry.size) { fitToPlot(in: geometry.size) }
            .onChange(of: plot.boundary) { fitToPlot(in: geometry.size) }
            .onChange(of: variant.id) { fitToPlot(in: geometry.size) }
        }
        .background(chrome.background)
    }

    // MARK: - Controls

    /// Collapsible, because it is screen-space furniture sitting on top of the
    /// drawing: at the default zoom it covers whatever is in that corner.
    private var legend: some View {
        let categories = orderedCategories()
        return VStack(alignment: .leading, spacing: 3) {
            Button {
                legendExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: legendExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text("Legend").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            if legendExpanded {
                ForEach(categories, id: \.self) { category in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CategoryStyle.of(category, colorScheme).fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(CategoryStyle.of(category, colorScheme).stroke, lineWidth: 1)
                            )
                            .frame(width: 11, height: 11)
                        Text(CategoryStyle.label(category)).font(.system(size: 10))
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(12)
        .opacity(categories.isEmpty ? 0 : 1)
    }

    private func orderedCategories() -> [ObjectCategory] {
        var seen: [ObjectCategory] = []
        for object in variant.objects where !seen.contains(object.category) {
            seen.append(object.category)
        }
        return seen
    }

    private func zoomControls(in size: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoom(by: 1.3, in: size) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { zoom(by: 1 / 1.3, in: size) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { fitToPlot(in: size) } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
        }
        .buttonStyle(.bordered)
        .padding(12)
    }

    private func zoom(by factor: Double, in size: CGSize) {
        viewport.zoom(by: factor, anchor: Point(x: Double(size.width) / 2, y: Double(size.height) / 2))
    }

    private func fitToPlot(in size: CGSize) {
        guard let bounds = plot.bounds, size.width > 0, size.height > 0 else { return }
        viewport.fit(bounds, in: Size(width: Double(size.width), height: Double(size.height)))
    }

    private func screen(_ point: Point) -> CGPoint {
        let projected = viewport.toScreen(point)
        return CGPoint(x: projected.x, y: projected.y)
    }

    // MARK: - Layers

    /// A grid at whatever round metre step reads well at this zoom — the same
    /// 1/2/5 sequence the scale bar uses, so the two always agree.
    private func drawGrid(_ context: GraphicsContext, size: CGSize) {
        let step = ScaleBar.niceLength(metresPerPoint: 1 / viewport.scale, targetScreenLength: 60, maxScreenLength: 120)
        guard step > 0 else { return }
        let topLeft = viewport.toWorld(Point(x: 0, y: 0))
        let bottomRight = viewport.toWorld(Point(x: Double(size.width), y: Double(size.height)))

        var path = Path()
        var x = (topLeft.x / step).rounded(.down) * step
        while x <= bottomRight.x {
            let screenX = CGFloat(viewport.toScreen(Point(x: x, y: 0)).x)
            path.move(to: CGPoint(x: screenX, y: 0))
            path.addLine(to: CGPoint(x: screenX, y: size.height))
            x += step
        }
        var y = (topLeft.y / step).rounded(.down) * step
        while y <= bottomRight.y {
            let screenY = CGFloat(viewport.toScreen(Point(x: 0, y: y)).y)
            path.move(to: CGPoint(x: 0, y: screenY))
            path.addLine(to: CGPoint(x: size.width, y: screenY))
            y += step
        }
        context.stroke(path, with: .color(chrome.grid), lineWidth: 1)
    }

    private func drawPlot(_ context: GraphicsContext) {
        var path = Path()
        path.addLines(plot.boundary.map(screen))
        path.closeSubpath()
        context.fill(path, with: .color(chrome.plotFill))
        context.stroke(path, with: .color(chrome.plotStroke), lineWidth: 2)
    }

    /// The river/lake/pond frontage, ported from the web app's WaterfrontZone.
    /// It belongs to the plot rather than to a variant — every variant of the
    /// same plot shares the same water — so it is drawn from `plot`, not from
    /// `variant.zones`, and it is the one thing here that survives a re-roll.
    /// Without it a dock sat on what looked like bare grass.
    private func drawWaterfront(_ context: GraphicsContext) {
        guard let waterfront = plot.waterfront,
              let zone = WaterfrontModel.zone(of: plot),
              zone.boundary.count > 2,
              let bounds = Rect(bounding: zone.boundary) else { return }

        // The bank: the part of the planning strip the water does not reach.
        // The flat plan keeps the strip visible — it is what the setbacks are
        // measured from — but the water inside it is the shape the other view
        // draws, so the two show the same river.
        var strip = Path()
        strip.addLines(zone.boundary.map(screen))
        strip.closeSubpath()
        let look = WaterPalette.of(waterfront.type)
        context.fill(strip, with: .color(look.bankColour.opacity(0.5)))
        context.stroke(strip, with: .color(look.bankColour), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        let shore = WaterfrontModel.shoreline(of: plot) ?? zone.boundary
        var surface = Path()
        surface.addLines(shore.map(screen))
        surface.closeSubpath()

        context.fill(surface, with: .color(look.shallowColour.opacity(0.65)))
        context.stroke(surface, with: .color(look.deepColour), lineWidth: 1.5)

        drawWaves(context, in: bounds, color: look.deepColour)

        // Named, because "river" and "pond" put very different constraints on
        // what can go next to them and the shape alone doesn't say which.
        let label = Text(waterfront.type.rawValue.capitalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(look.deepColour.opacity(0.9))
        context.draw(label, at: screen(Point(x: bounds.midX, y: bounds.midY)))
    }

    /// A chain of alternating quadratic bumps — the cheap way the web app
    /// draws a long wavy line, kept so the two renderings read as the same
    /// water. Laid out along whichever axis the strip is longer on.
    private func drawWaves(_ context: GraphicsContext, in bounds: Rect, color: Color) {
        let horizontal = bounds.width >= bounds.height
        let longLength = horizontal ? bounds.width : bounds.height
        let shortLength = horizontal ? bounds.height : bounds.width
        guard longLength * viewport.scale > 40, shortLength > 0 else { return }

        let margin = min(1, shortLength * 0.15)
        let amplitude = min(0.35, shortLength / 8)
        let usable = shortLength - margin * 2
        guard usable > 0 else { return }
        let rows = max(1, Int(usable / 2.2) + 1)
        let bumps = max(2, Int((longLength / 4).rounded()))
        let step = (longLength - margin * 2) / Double(bumps * 2)
        guard step > 0 else { return }

        var path = Path()
        for row in 0..<rows {
            let across = rows == 1
                ? (horizontal ? bounds.midY : bounds.midX)
                : (horizontal ? bounds.minY : bounds.minX) + margin + usable * Double(row) / Double(rows - 1)
            // One helper so the two orientations differ only in which
            // component the wave runs along, not in the wave itself.
            let point: (Double, Double) -> CGPoint = { along, offset in
                horizontal
                    ? self.screen(Point(x: along, y: across + offset))
                    : self.screen(Point(x: across + offset, y: along))
            }

            var along = (horizontal ? bounds.minX : bounds.minY) + margin
            path.move(to: point(along, 0))
            for bump in 0..<(bumps * 2) {
                let end = along + step
                path.addQuadCurve(
                    to: point(end, 0),
                    control: point(along + step / 2, bump % 2 == 0 ? -amplitude : amplitude)
                )
                along = end
            }
        }
        context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 1)
    }

    /// Zones (the future-expansion reserve today) sit under everything as a
    /// tinted, dashed region — they're areas the plan sets aside, not objects
    /// placed on it, and reading them as solid would misrepresent that.
    private func drawZones(_ context: GraphicsContext) {
        for zone in variant.zones {
            guard zone.boundary.count > 2 else { continue }
            var path = Path()
            path.addLines(zone.boundary.map(screen))
            path.closeSubpath()

            let style = CategoryStyle.of(ObjectCategory(zone: zone.category) ?? .futureExpansion, colorScheme)
            context.fill(path, with: .color(style.fill.opacity(0.45)))
            context.stroke(path, with: .color(style.stroke.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))

            if let bounds = Rect(bounding: zone.boundary), bounds.width * viewport.scale > 60 {
                let centre = screen(Point(x: bounds.midX, y: bounds.midY))
                context.draw(
                    Text(zone.label).font(.system(size: 9)).foregroundColor(chrome.furniture),
                    at: centre
                )
            }
        }
    }

    private func drawFences(_ context: GraphicsContext) {
        let style = CategoryStyle.of(.animal, colorScheme)
        for fence in variant.fences {
            var path = Path()
            path.addLines(fence.points.map(screen))
            context.stroke(
                path,
                with: .color(style.stroke.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, dash: fence.gated ? [5, 4] : [])
            )
        }
    }

    private func drawPaths(_ context: GraphicsContext) {
        let style = CategoryStyle.of(.access, colorScheme)
        for pathEntity in variant.paths {
            var path = Path()
            path.addLines(pathEntity.points.map(screen))
            let width = max(1.5, CGFloat(pathEntity.widthM * viewport.scale))
            context.stroke(path, with: .color(style.fill), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(style.stroke.opacity(0.45)), style: StrokeStyle(lineWidth: max(0.5, width * 0.08), lineCap: .round))
        }
    }

    /// Roof-mounted equipment (a solar array on the house) deliberately
    /// shares the building's footprint — the engine places it there and
    /// excludes it from overlap warnings, path routing and area accounting.
    /// Drawn like a ground object it just reads as two buildings piled on
    /// each other, so it gets a dashed, unfilled treatment on top instead.
    private func isRoofMounted(_ object: PlanObject) -> Bool {
        object.metadata["roofMounted"]?.boolValue == true
    }

    private func drawObjects(_ context: GraphicsContext) {
        // One occupancy map for every piece of text on the plan. Symbols are
        // added first because they are the thing a label would otherwise be
        // written straight on top of — which is exactly what happened before:
        // both the symbol and the label were anchored at the object's centre.
        var occupied: [CGRect] = []

        for object in variant.objects where !isRoofMounted(object) {
            drawFootprint(context, object: object, roofMounted: false)
        }
        for object in variant.objects where isRoofMounted(object) {
            drawFootprint(context, object: object, roofMounted: true)
        }
        for object in variant.objects {
            if let rect = symbolRect(for: object) { occupied.append(rect) }
        }

        drawLabels(context, occupied: &occupied)
        if showsDimensions { drawDimensionText(context, occupied: &occupied) }
    }

    private func drawFootprint(_ context: GraphicsContext, object: PlanObject, roofMounted: Bool) {
        var shape = Path()
        shape.addLines(object.transform.corners.map(screen))
        shape.closeSubpath()

        let style = CategoryStyle.of(object.category, colorScheme)
        if roofMounted {
            context.fill(shape, with: .color(style.fill.opacity(0.5)))
            context.stroke(shape, with: .color(style.stroke), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        } else {
            context.fill(shape, with: .color(style.fill.opacity(object.locked ? 0.55 : 1)))
            context.stroke(shape, with: .color(style.stroke), lineWidth: 1.2)
        }

        ObjectGlyphs.draw(
            context,
            object: object,
            frame: .plan(
                center: screen(object.transform.center),
                scale: viewport.scale,
                rotation: object.transform.rotationDeg * .pi / 180
            ),
            stroke: style.stroke
        )
        drawSymbol(context, object: object, style: style)

        if highlightedObjectIDs.contains(object.id) {
            context.stroke(shape, with: .color(.orange.opacity(0.45)), lineWidth: 9)
            context.stroke(shape, with: .color(.orange), lineWidth: 2)
        }
        if object.id == selectedObjectID {
            context.stroke(shape, with: .color(.accentColor), lineWidth: 2.5)
        }
        if showsDimensions { drawDimensionLines(context, for: object) }
    }

    /// A standard symbol per type, so a shape says what it is before anyone
    /// reads its label — and small objects, whose labels get skipped when
    /// space runs out, still identify themselves.
    private func symbolSize(for object: PlanObject) -> CGFloat? {
        let footprint = min(object.transform.width, object.transform.height) * viewport.scale
        guard footprint > 24 else { return nil }
        return min(20, max(10, footprint * 0.38))
    }

    private func symbolRect(for object: PlanObject) -> CGRect? {
        guard let size = symbolSize(for: object) else { return nil }
        let centre = screen(object.transform.center)
        return CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
    }

    private func drawSymbol(_ context: GraphicsContext, object: PlanObject, style: CategoryStyle) {
        guard let size = symbolSize(for: object) else { return }
        context.draw(
            Text(Image(systemName: ObjectSymbols.name(for: object)))
                .font(.system(size: size))
                .foregroundColor(style.stroke.opacity(0.8)),
            at: screen(object.transform.center)
        )
    }

    /// Dimension lines are cheap and never collide with text, so they're
    /// drawn with the footprint; their labels go through the shared
    /// occupancy pass at the end, where they have the lowest priority.
    private func drawDimensionLines(_ context: GraphicsContext, for object: PlanObject) {
        let corners = object.transform.corners
        guard corners.count == 4, object.transform.width * viewport.scale > 44 else { return }

        for (a, b) in [(corners[3], corners[2]), (corners[0], corners[3])] {
            var line = Path()
            line.move(to: screen(a))
            line.addLine(to: screen(b))
            context.stroke(line, with: .color(chrome.furniture.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
    }

    private func drawDimensionText(_ context: GraphicsContext, occupied: inout [CGRect]) {
        for object in variant.objects {
            let corners = object.transform.corners
            guard corners.count == 4, object.transform.width * viewport.scale > 44 else { continue }

            for (a, b, metres) in [
                (corners[3], corners[2], object.transform.width),
                (corners[0], corners[3], object.transform.height),
            ] {
                let text = "\(Int(metres.rounded())) m"
                let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let anchor = screen(mid)
                let size = CGSize(width: CGFloat(text.count) * 4.8 + 4, height: 10)
                let rect = CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2, width: size.width, height: size.height)
                // A dimension is the first thing worth dropping when the plan
                // gets crowded: the object's own name matters more.
                guard !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                occupied.append(rect)
                context.draw(
                    Text(text).font(.system(size: 8)).foregroundColor(chrome.furniture),
                    at: anchor
                )
            }
        }
    }

    /// One pass over every label, after all footprints are drawn, so a label
    /// is never buried under a later object — and so each one can be placed
    /// against the labels already committed. Without this, neighbours write
    /// over each other: a roof-mounted array's name lands exactly on the
    /// house's, and a bed's name lands on the shelter next to it.
    private func drawLabels(_ context: GraphicsContext, occupied: inout [CGRect]) {
        let byPriority = variant.objects.sorted {
            $0.transform.width * $0.transform.height > $1.transform.width * $1.transform.height
        }

        for object in byPriority {
            let widthOnScreen = CGFloat(object.transform.width * viewport.scale)
            let heightOnScreen = CGFloat(object.transform.height * viewport.scale)
            guard widthOnScreen > 26 else { continue }

            let textWidth = CGFloat(object.label.count) * 5.4
            let textSize = CGSize(width: textWidth + 4, height: 12)
            let centre = screen(object.transform.center)
            let symbolHeight = symbolSize(for: object) ?? 0
            // With a symbol at the centre, the label sits under it inside the
            // footprint when there's room for both stacked; otherwise it goes
            // outside. Trying the centre first is what wrote "Goat Paddock"
            // across its own paw mark.
            let insideOffset = symbolHeight / 2 + 9
            let fitsInside = textWidth + 8 <= widthOnScreen
                && heightOnScreen > symbolHeight + 26

            var candidates: [CGPoint] = []
            if fitsInside {
                candidates.append(CGPoint(x: centre.x, y: centre.y + insideOffset))
            }
            candidates.append(CGPoint(x: centre.x, y: centre.y + heightOnScreen / 2 + 8))
            candidates.append(CGPoint(x: centre.x, y: centre.y - heightOnScreen / 2 - 8))
            candidates.append(CGPoint(x: centre.x + widthOnScreen / 2 + textWidth / 2 + 6, y: centre.y))
            candidates.append(CGPoint(x: centre.x - widthOnScreen / 2 - textWidth / 2 - 6, y: centre.y))

            let spot = candidates.first { candidate in
                let rect = CGRect(
                    x: candidate.x - textSize.width / 2,
                    y: candidate.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                return !occupied.contains { $0.intersects(rect) }
            }

            // Every position taken: skip rather than stack text on text. The
            // object is still selectable, and its name shows in the bar below.
            guard let position = spot else { continue }
            occupied.append(CGRect(
                x: position.x - textSize.width / 2,
                y: position.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ))

            context.draw(
                Text(object.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(chrome.label),
                at: position
            )
        }
    }

    private func drawScaleBar(_ context: GraphicsContext, size: CGSize) {
        let metres = ScaleBar.niceLength(metresPerPoint: 1 / viewport.scale)
        let length = CGFloat(metres * viewport.scale)
        let origin = CGPoint(x: 20, y: size.height - 24)

        var path = Path()
        path.move(to: CGPoint(x: origin.x, y: origin.y - 4))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y + 4))
        path.move(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + length, y: origin.y))
        path.move(to: CGPoint(x: origin.x + length, y: origin.y - 4))
        path.addLine(to: CGPoint(x: origin.x + length, y: origin.y + 4))
        context.stroke(path, with: .color(chrome.furniture), lineWidth: 1.5)

        // niceLength only ever returns 1/2/5 × a power of ten, so a sub-metre
        // step is 0.5/0.2/0.1 — all of which print cleanly as-is.
        let label = metres < 1 ? "\(metres) m" : "\(Int(metres)) m"
        context.draw(
            Text(label).font(.system(size: 10)).foregroundColor(chrome.furniture),
            at: CGPoint(x: origin.x + length / 2, y: origin.y - 12)
        )
    }

    private func drawNorthArrow(_ context: GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width - 34, y: 40)
        let radians = plot.northAngleDeg * .pi / 180
        // North is "up" on screen, rotated by the plot's own north angle.
        func offset(_ angle: Double, _ length: Double) -> CGPoint {
            CGPoint(
                x: centre.x + CGFloat(sin(angle) * length),
                y: centre.y - CGFloat(cos(angle) * length)
            )
        }
        let tip = offset(radians, 16)
        let tail = offset(radians, -12)
        let left = offset(radians + 2.4, 7)
        let right = offset(radians - 2.4, 7)

        var shaft = Path()
        shaft.move(to: tail)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(chrome.furniture), lineWidth: 1.5)

        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(chrome.furniture))

        context.draw(
            Text("N").font(.system(size: 10, weight: .semibold)).foregroundColor(chrome.furniture),
            at: CGPoint(x: centre.x, y: centre.y + 24)
        )
    }
}
