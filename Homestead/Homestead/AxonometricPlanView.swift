//
//  AxonometricPlanView.swift
//  Homestead
//
//  The same plan with height: a dimetric projection, drawn back-to-front,
//  with shaded walls and roofs. Not SceneKit — a real 3D scene graph would
//  drag in a framework Apple is winding down, and an architectural
//  axonometric is the convention for a site plan anyway: no perspective
//  distortion, every metre the same length wherever it sits.
//
//  The projection is linear, so world coordinates are converted to
//  "axonometric metres" and then run through exactly the same Viewport the
//  flat plan uses — pan, zoom and fit-to-plot come along unchanged.
//

import SwiftUI
import HomesteadEngine
import HomesteadCore

/// x right-and-down, y left-and-down, z straight up: the classic 30° site
/// axonometric.
enum Axonometry {
    static let cosA = 0.866   // cos 30°
    static let sinA = 0.5     // sin 30°

    static func project(x: Double, y: Double, z: Double = 0) -> Point {
        Point(x: (x - y) * cosA, y: (x + y) * sinA - z)
    }

    static func project(_ point: Point, z: Double = 0) -> Point {
        project(x: point.x, y: point.y, z: z)
    }

    /// Inverse at ground level, for hit-testing a click.
    static func groundPoint(_ axo: Point) -> Point {
        let a = axo.x / cosA
        let b = axo.y / sinA
        return Point(x: (a + b) / 2, y: (b - a) / 2)
    }
}

struct AxonometricPlanView: View {
    let plot: Plot
    let variant: Variant
    @Binding var viewport: Viewport
    @Binding var selectedObjectID: String?
    var showsDimensions: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragAnchor: CGSize = .zero
    @State private var magnifyAnchor: CGFloat = 1

    private var chrome: CanvasChrome { CanvasChrome.of(colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGround(context)
                drawFlatFeatures(context)
                drawMassing(context)
                drawScaleNote(context, size: size)
                drawCompass(context, size: size)
            }
            .contentShape(Rectangle())
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
                        let axo = viewport.toWorld(Point(x: Double(value.location.x), y: Double(value.location.y)))
                        selectedObjectID = HitTesting.hitTest(Axonometry.groundPoint(axo), in: variant.objects)
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
            .onAppear { fit(in: geometry.size) }
            .onChange(of: geometry.size) { fit(in: geometry.size) }
            .onChange(of: plot.boundary) { fit(in: geometry.size) }
            .onChange(of: variant.id) { fit(in: geometry.size) }
        }
        .background(chrome.background)
    }

    // MARK: - Camera

    private func fit(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let projected = plot.boundary.map { Axonometry.project($0) }
        // Tall buildings stand up out of the plot's own footprint, so the
        // framed box is padded upward rather than fitted to the ground alone.
        guard var bounds = Rect(bounding: projected) else { return }
        bounds = Rect(minX: bounds.minX, minY: bounds.minY - 8, maxX: bounds.maxX, maxY: bounds.maxY)
        viewport.fit(bounds, in: Size(width: Double(size.width), height: Double(size.height)), padding: 36)
    }

    private func screen(_ world: Point, z: Double = 0) -> CGPoint {
        let axo = Axonometry.project(world, z: z)
        let point = viewport.toScreen(axo)
        return CGPoint(x: point.x, y: point.y)
    }

    private func zoomControls(in size: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoom(by: 1.3, in: size) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { zoom(by: 1 / 1.3, in: size) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { fit(in: size) } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
        }
        .buttonStyle(.bordered)
        .padding(12)
    }

    private func zoom(by factor: Double, in size: CGSize) {
        viewport.zoom(by: factor, anchor: Point(x: Double(size.width) / 2, y: Double(size.height) / 2))
    }

    // MARK: - Layers

    private func drawGround(_ context: GraphicsContext) {
        var path = Path()
        path.addLines(plot.boundary.map { screen($0) })
        path.closeSubpath()
        context.fill(path, with: .color(chrome.plotFill))
        context.stroke(path, with: .color(chrome.plotStroke), lineWidth: 1.5)

        guard let bounds = plot.bounds else { return }
        let step = ScaleBar.niceLength(metresPerPoint: 1 / viewport.scale, targetScreenLength: 70, maxScreenLength: 140)
        guard step > 0 else { return }

        var grid = Path()
        var x = bounds.minX
        while x <= bounds.maxX {
            grid.move(to: screen(Point(x: x, y: bounds.minY)))
            grid.addLine(to: screen(Point(x: x, y: bounds.maxY)))
            x += step
        }
        var y = bounds.minY
        while y <= bounds.maxY {
            grid.move(to: screen(Point(x: bounds.minX, y: y)))
            grid.addLine(to: screen(Point(x: bounds.maxX, y: y)))
            y += step
        }
        context.stroke(grid, with: .color(chrome.grid), lineWidth: 0.8)
    }

    private func drawFlatFeatures(_ context: GraphicsContext) {
        let pathStyle = CategoryStyle.of(.access, colorScheme)
        for pathEntity in variant.paths {
            var line = Path()
            line.addLines(pathEntity.points.map { screen($0, z: 0.02) })
            context.stroke(
                line,
                with: .color(pathStyle.fill),
                style: StrokeStyle(lineWidth: max(1.5, CGFloat(pathEntity.widthM * viewport.scale * 0.9)), lineCap: .round, lineJoin: .round)
            )
        }

        let fenceStyle = CategoryStyle.of(.animal, colorScheme)
        let painter = AxoPainter(context: context, project: { point, z in self.screen(point, z: z) }, scale: viewport.scale)
        for fence in variant.fences {
            AxoKit.fence(painter, points: fence.points, height: 1.4, color: fenceStyle.stroke.opacity(0.9))
        }
    }

    /// Back to front: an object further from the viewer is drawn first, so
    /// nearer massing paints over it. Depth in this projection is x + y.
    private func drawMassing(_ context: GraphicsContext) {
        let ordered = variant.objects.sorted { a, b in
            let da = a.transform.x + a.transform.y
            let db = b.transform.x + b.transform.y
            if da == db { return a.id < b.id }
            return da < db
        }

        for object in ordered {
            let style = CategoryStyle.of(object.category, colorScheme)
            let base = Massing.baseElevation(for: object, among: variant.objects)
            let corners = object.transform.corners
            let selected = object.id == selectedObjectID
            let painter = AxoPainter(context: context, project: { point, z in self.screen(point, z: z) }, scale: viewport.scale)
            let roofTones = Massing.roofColor(for: object)
            let roof = Color(hex: colorScheme == .dark ? roofTones.dark : roofTones.light)

            switch Massing.form(for: object) {
            case .flat(let height):
                drawTopFace(context, corners: corners, z: base + height, style: style, object: object, selected: selected, lit: 0)

            case .block(let height):
                drawWalls(context, corners: corners, from: base, to: base + height, style: style)
                drawTopFace(context, corners: corners, z: base + height, style: style, object: object, selected: selected, lit: 0.10)

            case .gabled(let eaves, let ridge):
                AxoKit.gabledBuilding(
                    painter,
                    object: object,
                    base: base,
                    eaves: eaves,
                    ridge: ridge,
                    wall: style.fill,
                    wallOutline: style.stroke,
                    roof: roof,
                    glazed: false
                )
                if ["house", "house-l", "banya", "smokehouse"].contains(object.typeId) {
                    AxoKit.chimney(painter, object: object, base: base, ridgeZ: base + ridge, wall: style.fill, outline: style.stroke)
                }
                if selected { outlineFootprint(context, corners: corners, z: base) }

            case .glass(let eaves, let ridge):
                AxoKit.gabledBuilding(
                    painter,
                    object: object,
                    base: base,
                    eaves: eaves,
                    ridge: ridge,
                    wall: style.fill.opacity(0.8),
                    wallOutline: style.stroke,
                    roof: Color(hex: 0xbfe3e8).opacity(0.75),
                    glazed: true
                )
                if selected { outlineFootprint(context, corners: corners, z: base) }

            case .cylinder(let height, let radiusScale):
                let radius = min(object.transform.width, object.transform.height) * radiusScale
                painter.cylinder(
                    center: object.transform.center,
                    radius: radius,
                    from: base,
                    to: base + height,
                    fill: style.fill,
                    outline: style.stroke,
                    shade: 0.22
                )
                if selected { outlineFootprint(context, corners: corners, z: base) }

            case .rows(let height, _):
                AxoKit.plantedRows(
                    painter,
                    object: object,
                    base: base,
                    height: height,
                    soil: style.fill,
                    crop: style.stroke.opacity(0.85),
                    outline: style.stroke
                )
                if selected { outlineFootprint(context, corners: corners, z: base) }

            case .canopy(let height, let radius, let conifer):
                drawOrchard(painter, object: object, height: height, radius: radius, conifer: conifer, style: style)
                if selected { outlineFootprint(context, corners: corners, z: base) }
            }

            if showsDimensions { drawDimensions(context, for: object, z: base) }
        }
    }

    private func outlineFootprint(_ context: GraphicsContext, corners: [Point], z: Double) {
        var path = Path()
        path.addLines(corners.map { screen($0, z: z) })
        path.closeSubpath()
        context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
    }

    private func drawOrchard(_ painter: AxoPainter, object: PlanObject, height: Double, radius: Double, conifer: Bool, style: CategoryStyle) {
        let w = object.transform.width
        let h = object.transform.height
        let cols = min(4, max(1, Int(w / 5)))
        let rows = min(4, max(1, Int(h / 5)))
        let centre = object.transform.center

        // Back to front within the grove, so near trees overlap far ones.
        var positions: [Point] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let x = cols == 1 ? centre.x : centre.x - w / 2 + 1.5 + Double(c) * (w - 3) / Double(cols - 1)
                let y = rows == 1 ? centre.y : centre.y - h / 2 + 1.5 + Double(r) * (h - 3) / Double(rows - 1)
                positions.append(Point(x: x, y: y))
            }
        }
        for position in positions.sorted(by: { $0.x + $0.y < $1.x + $1.y }) {
            AxoKit.tree(painter, at: position, height: height, radius: radius, conifer: conifer, foliage: style.fill, outline: style.stroke)
        }
    }

    private func drawWalls(_ context: GraphicsContext, corners: [Point], from base: Double, to top: Double, style: CategoryStyle) {
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            var face = Path()
            face.addLines([screen(a, z: base), screen(b, z: base), screen(b, z: top), screen(a, z: top)])
            face.closeSubpath()

            // Two wall orientations, two shades — enough to read as solid
            // without needing real lighting.
            let shade = i % 2 == 0 ? 0.16 : 0.30
            context.fill(face, with: .color(style.fill))
            context.fill(face, with: .color(.black.opacity(shade)))
            context.stroke(face, with: .color(style.stroke.opacity(0.8)), lineWidth: 0.8)
        }
    }

    private func drawTopFace(
        _ context: GraphicsContext,
        corners: [Point],
        z: Double,
        style: CategoryStyle,
        object: PlanObject,
        selected: Bool,
        lit: Double
    ) {
        var face = Path()
        face.addLines(corners.map { screen($0, z: z) })
        face.closeSubpath()
        context.fill(face, with: .color(style.fill))
        if lit > 0 { context.fill(face, with: .color(.white.opacity(lit))) }
        context.stroke(face, with: .color(style.stroke), lineWidth: selected ? 2.2 : 0.9)
        if selected {
            context.stroke(face, with: .color(.accentColor), lineWidth: 2.2)
        }

        drawSymbol(context, object: object, at: z, style: style)
    }

    private func drawSymbol(_ context: GraphicsContext, object: PlanObject, at z: Double, style: CategoryStyle) {
        let footprint = min(object.transform.width, object.transform.height) * viewport.scale
        guard footprint > 26 else { return }
        let size = min(22, max(11, footprint * 0.42))
        context.draw(
            Text(Image(systemName: ObjectSymbols.name(for: object)))
                .font(.system(size: size))
                .foregroundColor(style.stroke.opacity(0.85)),
            at: screen(object.transform.center, z: z)
        )
    }

    /// Width and depth called out along the two ground edges, in the same
    /// axonometric frame, so they read as lying on the plan rather than
    /// floating over it.
    private func drawDimensions(_ context: GraphicsContext, for object: PlanObject, z: Double) {
        let corners = object.transform.corners
        guard corners.count == 4, object.transform.width * viewport.scale > 40 else { return }

        let pairs = [(corners[3], corners[2], object.transform.width), (corners[0], corners[3], object.transform.height)]
        for (a, b, metres) in pairs {
            var line = Path()
            line.move(to: screen(a, z: z))
            line.addLine(to: screen(b, z: z))
            context.stroke(line, with: .color(chrome.furniture.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            context.draw(
                Text("\(Int(metres.rounded())) m").font(.system(size: 8)).foregroundColor(chrome.furniture),
                at: screen(mid, z: z)
            )
        }
    }

    private func drawScaleNote(_ context: GraphicsContext, size: CGSize) {
        let metres = ScaleBar.niceLength(metresPerPoint: 1 / viewport.scale)
        context.draw(
            Text("Axonometric · grid \(Int(metres)) m").font(.system(size: 10)).foregroundColor(chrome.furniture),
            at: CGPoint(x: 76, y: size.height - 20)
        )
    }

    private func drawCompass(_ context: GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width - 42, y: 44)
        // North runs along -y in world space; project it to get its screen
        // direction under this rotation, so the arrow matches the drawing.
        let origin = Axonometry.project(x: 0, y: 0)
        let north = Axonometry.project(x: 0, y: -1)
        let dx = north.x - origin.x
        let dy = north.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let tip = CGPoint(x: centre.x + CGFloat(dx / length * 18), y: centre.y + CGFloat(dy / length * 18))

        var shaft = Path()
        shaft.move(to: centre)
        shaft.addLine(to: tip)
        context.stroke(shaft, with: .color(chrome.furniture), lineWidth: 1.5)
        context.draw(
            Text("N").font(.system(size: 10, weight: .semibold)).foregroundColor(chrome.furniture),
            at: CGPoint(x: tip.x, y: tip.y - 10)
        )
    }
}
