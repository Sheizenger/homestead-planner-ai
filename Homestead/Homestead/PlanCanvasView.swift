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
//  North arrow and scale bar are drawn in screen space, deliberately outside
//  the viewport transform, so they stay put and stay legible at any zoom
//  (see Viewport's own doc comment).
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

struct PlanCanvasView: View {
    let plot: Plot
    let variant: Variant
    @Binding var viewport: Viewport
    @Binding var selectedObjectID: String?

    @State private var dragAnchor: CGSize = .zero
    @State private var magnifyAnchor: CGFloat = 1

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
            .overlay(alignment: .topLeading) {
                legend.allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                zoomControls(in: geometry.size)
            }
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
                        let center = Point(x: Double(geometry.size.width) / 2, y: Double(geometry.size.height) / 2)
                        viewport.zoom(by: Double(factor), anchor: center)
                    }
                    .onEnded { _ in magnifyAnchor = 1 }
            )
            .onAppear { fitToPlot(in: geometry.size) }
            .onChange(of: variant.id) { fitToPlot(in: geometry.size) }
        }
        .background(Color(white: 0.99))
    }

    /// Only the categories this plan actually contains — a fixed legend of
    /// all thirteen would mostly list things that aren't on screen.
    private var legend: some View {
        let categories = orderedCategories()
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: category))
                        .frame(width: 10, height: 10)
                    Text(name(for: category)).font(.system(size: 10))
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

    private func name(for category: ObjectCategory) -> String {
        switch category {
        case .residential: return "Living"
        case .access: return "Access"
        case .foodAnnual: return "Annual crops"
        case .foodPerennial: return "Perennial crops"
        case .greenhouse: return "Greenhouse"
        case .animal: return "Animals"
        case .utility: return "Utilities"
        case .water: return "Water"
        case .energy: return "Energy"
        case .storage: return "Storage"
        case .leisure: return "Leisure"
        case .futureExpansion: return "Future expansion"
        case .fence: return "Fence"
        case .path: return "Path"
        }
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
        guard let bounds = plot.bounds else { return }
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
        context.stroke(path, with: .color(Color(white: 0.93)), lineWidth: 1)
    }

    private func drawPlot(_ context: GraphicsContext) {
        var path = Path()
        path.addLines(plot.boundary.map(screen))
        path.closeSubpath()
        context.fill(path, with: .color(Color(white: 0.965)))
        context.stroke(path, with: .color(Color(white: 0.45)), lineWidth: 2)
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

            let tint = color(for: ObjectCategory(zone: zone.category) ?? .futureExpansion)
            context.fill(path, with: .color(tint.opacity(0.18)))
            context.stroke(path, with: .color(tint.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))

            if let bounds = Rect(bounding: zone.boundary), bounds.width * viewport.scale > 60 {
                let center = screen(Point(x: bounds.midX, y: bounds.midY))
                context.draw(
                    Text(zone.label).font(.system(size: 9)).foregroundColor(Color(white: 0.4)),
                    at: center
                )
            }
        }
    }

    private func drawFences(_ context: GraphicsContext) {
        for fence in variant.fences {
            var path = Path()
            path.addLines(fence.points.map(screen))
            context.stroke(
                path,
                with: .color(Color(red: 0.45, green: 0.32, blue: 0.2)),
                style: StrokeStyle(lineWidth: 1.5, dash: fence.gated ? [5, 4] : [])
            )
        }
    }

    private func drawPaths(_ context: GraphicsContext) {
        for pathEntity in variant.paths {
            var path = Path()
            path.addLines(pathEntity.points.map(screen))
            let width = max(1.5, CGFloat(pathEntity.widthM * viewport.scale))
            context.stroke(path, with: .color(Color(white: 0.78)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawObjects(_ context: GraphicsContext) {
        for object in variant.objects {
            var shape = Path()
            shape.addLines(object.transform.corners.map(screen))
            shape.closeSubpath()

            // Structures read as solid; growing areas are deliberately
            // lighter so a 200 m² potato patch doesn't visually outweigh the
            // house standing next to it.
            let tint = color(for: object.category)
            let growingAreas: Set<ObjectCategory> = [.foodAnnual, .foodPerennial, .greenhouse]
            let isGrowingArea = growingAreas.contains(object.category)
            let fillOpacity = object.locked ? 0.3 : (isGrowingArea ? 0.4 : 0.78)
            context.fill(shape, with: .color(tint.opacity(fillOpacity)))
            context.stroke(shape, with: .color(tint.opacity(isGrowingArea ? 0.8 : 1)), lineWidth: isGrowingArea ? 1 : 1.6)

            if object.id == selectedObjectID {
                context.stroke(shape, with: .color(.accentColor), lineWidth: 3)
            }

            drawLabel(context, for: object)
        }
    }

    /// Inside the object when it fits, just below it when it doesn't — the
    /// alternative (always centred) overflows small objects and collides
    /// with whatever is drawn next to them.
    private func drawLabel(_ context: GraphicsContext, for object: PlanObject) {
        let widthOnScreen = CGFloat(object.transform.width * viewport.scale)
        let heightOnScreen = CGFloat(object.transform.height * viewport.scale)
        guard widthOnScreen > 22 else { return }

        let estimatedTextWidth = CGFloat(object.label.count) * 5.4
        let center = screen(object.transform.center)
        let fitsInside = estimatedTextWidth + 6 <= widthOnScreen && heightOnScreen > 14
        let position = fitsInside
            ? center
            : CGPoint(x: center.x, y: center.y + heightOnScreen / 2 + 7)

        context.draw(
            Text(object.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(white: 0.15)),
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
        context.stroke(path, with: .color(Color(white: 0.35)), lineWidth: 1.5)

        // niceLength only ever returns 1/2/5 × a power of ten, so a sub-metre
        // step is 0.5/0.2/0.1 — all of which print cleanly as-is.
        let label = metres < 1 ? "\(metres) m" : "\(Int(metres)) m"
        context.draw(
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.35)),
            at: CGPoint(x: origin.x + length / 2, y: origin.y - 12)
        )
    }

    private func drawNorthArrow(_ context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width - 34, y: 40)
        let radians = plot.northAngleDeg * .pi / 180
        // North is "up" on screen, rotated by the plot's own north angle.
        func offset(_ angle: Double, _ length: Double) -> CGPoint {
            CGPoint(
                x: center.x + CGFloat(sin(angle) * length),
                y: center.y - CGFloat(cos(angle) * length)
            )
        }
        let tip = offset(radians, 16)
        let tail = offset(radians, -12)
        let left = offset(radians + 2.4, 7)
        let right = offset(radians - 2.4, 7)

        var shaft = Path()
        shaft.move(to: tail)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(Color(white: 0.35)), lineWidth: 1.5)

        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(Color(white: 0.35)))

        context.draw(
            Text("N").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(white: 0.35)),
            at: CGPoint(x: center.x, y: center.y + 24)
        )
    }

    private func color(for category: ObjectCategory) -> Color {
        switch category {
        case .residential: return Color(red: 0.85, green: 0.52, blue: 0.24)
        case .access: return Color(white: 0.55)
        case .foodAnnual: return Color(red: 0.45, green: 0.68, blue: 0.32)
        case .foodPerennial: return Color(red: 0.25, green: 0.5, blue: 0.26)
        case .greenhouse: return Color(red: 0.36, green: 0.72, blue: 0.66)
        case .animal: return Color(red: 0.68, green: 0.5, blue: 0.32)
        case .utility: return Color(red: 0.36, green: 0.5, blue: 0.78)
        case .water: return Color(red: 0.3, green: 0.62, blue: 0.8)
        case .energy: return Color(red: 0.86, green: 0.72, blue: 0.28)
        case .storage: return Color(white: 0.52)
        case .leisure: return Color(red: 0.6, green: 0.45, blue: 0.72)
        case .futureExpansion: return Color(white: 0.8)
        case .fence, .path: return Color(white: 0.6)
        }
    }
}
