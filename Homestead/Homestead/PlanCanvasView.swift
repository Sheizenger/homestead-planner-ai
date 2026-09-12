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

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragAnchor: CGSize = .zero
    @State private var magnifyAnchor: CGFloat = 1

    private var chrome: CanvasChrome { CanvasChrome.of(colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGrid(context, size: size)
                drawPlot(context)
                drawZones(context)
                drawFences(context)
                drawPaths(context)
                drawObjects(context)
                drawScaleBar(context, size: size)
                drawNorthArrow(context, size: size)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) { legend.allowsHitTesting(false) }
            .overlay(alignment: .bottomTrailing) { zoomControls(in: geometry.size) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - dragAnchor.width,
                            height: value.translation.height - dragAnchor.height
                        )
                        dragAnchor = value.translation
                        viewport.pan(byScreen: Point(x: Double(delta.width), y: Double(delta.height)))
                    }
                    .onEnded { value in
                        dragAnchor = .zero
                        let moved = abs(value.translation.width) + abs(value.translation.height)
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

    private var legend: some View {
        let categories = orderedCategories()
        return VStack(alignment: .leading, spacing: 3) {
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

    private func drawObjects(_ context: GraphicsContext) {
        for object in variant.objects {
            var shape = Path()
            shape.addLines(object.transform.corners.map(screen))
            shape.closeSubpath()

            let style = CategoryStyle.of(object.category, colorScheme)
            context.fill(shape, with: .color(style.fill.opacity(object.locked ? 0.55 : 1)))
            context.stroke(shape, with: .color(style.stroke), lineWidth: 1.2)

            ObjectGlyphs.draw(
                context,
                object: object,
                frame: GlyphFrame(
                    center: screen(object.transform.center),
                    scale: viewport.scale,
                    rotation: object.transform.rotationDeg * .pi / 180
                ),
                stroke: style.stroke
            )

            if object.id == selectedObjectID {
                context.stroke(shape, with: .color(.accentColor), lineWidth: 2.5)
            }

            drawLabel(context, for: object)
        }
    }

    /// Inside the object when it fits, just below it when it doesn't — the
    /// first pass centred every label regardless, so a shed's name overflowed
    /// its own footprint and collided with whatever sat beside it.
    private func drawLabel(_ context: GraphicsContext, for object: PlanObject) {
        let widthOnScreen = CGFloat(object.transform.width * viewport.scale)
        let heightOnScreen = CGFloat(object.transform.height * viewport.scale)
        guard widthOnScreen > 26 else { return }

        let estimatedTextWidth = CGFloat(object.label.count) * 5.4
        let centre = screen(object.transform.center)
        let fitsInside = estimatedTextWidth + 8 <= widthOnScreen && heightOnScreen > 26
        let position = fitsInside
            ? centre
            : CGPoint(x: centre.x, y: centre.y + heightOnScreen / 2 + 8)

        context.draw(
            Text(object.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(chrome.label),
            at: position
        )
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
