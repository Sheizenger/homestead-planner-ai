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
    /// See `PlanCanvasView` — the objects a selected warning is about.
    var highlightedObjectIDs: Set<String> = []
    var showsDimensions: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragAnchor: CGSize = .zero
    @State private var magnifyAnchor: CGFloat = 1

    private var chrome: CanvasChrome { CanvasChrome.of(colorScheme) }

    /// The scene is lit by the sun, not by the app's appearance setting. Dark
    /// mode's palette exists so a *document* doesn't glare at you at night; a
    /// view of a place in daylight is not a document, and rendering it in
    /// muted dark-mode fills is what made this look like a wireframe with
    /// lumps on it. The chrome around it — background, scale note, compass —
    /// still follows the user's theme, which is the part that actually sits
    /// next to the rest of the UI.
    private var daylight: ColorScheme { .light }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawGround(context)
                drawWater(context)
                drawFlatFeatures(context)
                drawShadows(context)
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
        .background(sky)
    }

    /// A sky behind the scene rather than a panel colour. The land is a solid
    /// block sitting in front of something; on a flat fill it reads as a
    /// sticker. Follows the user's theme — the scene stays in daylight, but
    /// at night it sits against a dusk sky rather than a white one.
    private var sky: LinearGradient {
        let top = colorScheme == .dark ? Color(hex: 0x1d2836) : Color(hex: 0xcfe3f2)
        let bottom = colorScheme == .dark ? Color(hex: 0x2b3446) : Color(hex: 0xeef3e8)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Camera

    private func fit(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let projected = plot.boundary.map { Axonometry.project($0) }
        // Tall buildings stand up out of the plot's own footprint, so the
        // framed box is padded upward rather than fitted to the ground alone.
        guard var bounds = Rect(bounding: projected) else { return }
        // Padded up for tall buildings and down for the thickness of the
        // block of land, so neither gets cropped by fit-to-plot.
        bounds = Rect(minX: bounds.minX, minY: bounds.minY - 8, maxX: bounds.maxX, maxY: bounds.maxY + Self.slabDepth)
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

    /// The plot as a solid block of land rather than an outline on a page.
    /// Every isometric reference does this: the ground has thickness, with
    /// soil and rock in the cut faces, and it is what stops the scene reading
    /// as objects floating on a background. Drawn from the boundary, so an
    /// L-shaped plot is an L-shaped block.
    private func drawGround(_ context: GraphicsContext) {
        let boundary = plot.boundary
        guard boundary.count >= 3 else { return }
        let painter = AxoPainter(context: context, project: { point, z in self.screen(point, z: z) }, scale: viewport.scale)

        // Only the edges facing the viewer have a visible cut face; the far
        // ones are hidden behind the slab's own top.
        let edges = (0..<boundary.count).map { (boundary[$0], boundary[($0 + 1) % boundary.count]) }
        for edge in edges.sorted(by: { edgeDepth($0) < edgeDepth($1) }) {
            let normal = AxoLight.wallNormal(from: edge.0, to: edge.1)
            // Screen-space test: the face is visible when its outward normal
            // points toward the viewer, which in this projection is +x +y.
            guard normal.x + normal.y > 0 else { continue }
            painter.face(
                [(edge.0, 0), (edge.1, 0), (edge.1, -Self.slabDepth), (edge.0, -Self.slabDepth)],
                fill: Self.soil,
                shade: AxoLight.shade(normal: normal),
                outline: Self.soilEdge,
                lineWidth: 0.8,
                material: .brick,
                seed: "slab"
            )
        }

        var path = Path()
        path.addLines(boundary.map { screen($0) })
        path.closeSubpath()
        context.fill(path, with: .color(Self.grass))
        context.stroke(path, with: .color(Self.grassEdge), lineWidth: 1.2)
        drawGrass(context)

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
        context.stroke(grid, with: .color(.black.opacity(0.06)), lineWidth: 0.8)
    }

    /// How thick the block of land is, in metres. Deep enough to read as
    /// ground, shallow enough not to dominate a 40 m plot.
    private static let slabDepth = 2.6

    // The 3D view uses its own daylight palette rather than the plan's
    // category colours for the land itself. The categories carry meaning for
    // the *objects* and stay; grass and soil carry none, and borrowing the
    // plan's neutral greys for them is what made the scene look like a
    // wireframe with lumps on it.
    private static let grass = Color(hex: 0x7ab648)
    private static let grassEdge = Color(hex: 0x5d9436)
    private static let grassDark = Color(hex: 0x69a63d)
    private static let soil = Color(hex: 0x8a6446)
    private static let soilEdge = Color(hex: 0x6d4e36)

    private func edgeDepth(_ edge: (Point, Point)) -> Double {
        (edge.0.x + edge.0.y + edge.1.x + edge.1.y) / 2
    }

    /// Patches of a second green, then tufts. The references never use one
    /// flat green — the variation is what keeps a large empty plot from
    /// reading as a blank fill, and it costs a few dozen paths.
    private func drawGrass(_ context: GraphicsContext) {
        guard let bounds = plot.bounds, viewport.scale > 1.2 else { return }
        let area = bounds.width * bounds.height
        let patchCount = min(40, max(6, Int(area / 90)))

        for index in 0..<patchCount {
            let cx = bounds.minX + AxoNoise.value("patch", index, 1) * bounds.width
            let cy = bounds.minY + AxoNoise.value("patch", index, 2) * bounds.height
            let centre = Point(x: cx, y: cy)
            guard Polygon.contains(centre, polygon: plot.boundary) else { continue }
            let radius = 2.5 + AxoNoise.value("patch", index, 3) * 5

            var blob = Path()
            for step in 0...10 {
                let angle = Double(step) / 10 * 2 * .pi
                let wobble = radius * (0.78 + AxoNoise.value("patch", index, 10 + step) * 0.44)
                let point = Point(x: cx + cos(angle) * wobble, y: cy + sin(angle) * wobble)
                let screenPoint = screen(point)
                if step == 0 { blob.move(to: screenPoint) } else { blob.addLine(to: screenPoint) }
            }
            blob.closeSubpath()
            context.fill(blob, with: .color(Self.grassDark.opacity(0.55)))
        }

        guard viewport.scale > 3.5 else { return }
        let tuftCount = min(280, max(20, Int(area / 14)))
        var tufts = Path()
        for index in 0..<tuftCount {
            let point = Point(
                x: bounds.minX + AxoNoise.value("tuft", index, 1) * bounds.width,
                y: bounds.minY + AxoNoise.value("tuft", index, 2) * bounds.height
            )
            guard Polygon.contains(point, polygon: plot.boundary) else { continue }
            let base = screen(point)
            let height = CGFloat((0.24 + AxoNoise.value("tuft", index, 3) * 0.22) * viewport.scale)
            for blade in -1...1 {
                tufts.move(to: base)
                tufts.addLine(to: CGPoint(x: base.x + CGFloat(blade) * height * 0.45, y: base.y - height))
            }
        }
        context.stroke(tufts, with: .color(Self.grassEdge.opacity(0.75)), lineWidth: 1)
    }

    /// The plot's waterfront, sunk slightly below grade so it reads as water
    /// rather than as a blue paving slab — the one place this view deliberately
    /// goes below z = 0. Drawn from `plot` rather than `variant`, because the
    /// water is a property of the land and every variant shares it.
    private func drawWater(_ context: GraphicsContext) {
        guard let waterfront = plot.waterfront,
              let zone = WaterfrontModel.zone(of: plot),
              zone.boundary.count > 2,
              let bounds = Rect(bounding: zone.boundary) else { return }

        let surface = -0.15
        var basin = Path()
        basin.addLines(zone.boundary.map { screen($0, z: surface) })
        basin.closeSubpath()

        let style = CategoryStyle.of(.water, daylight)
        context.fill(basin, with: .color(style.fill.opacity(0.75)))
        context.stroke(basin, with: .color(style.stroke), lineWidth: 1.2)

        drawWaves(context, in: bounds, z: surface, color: style.stroke)

        context.draw(
            Text(waterfront.type.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(style.stroke.opacity(0.85)),
            at: screen(Point(x: bounds.midX, y: bounds.midY), z: surface)
        )
    }

    /// Same alternating-bump wave the 2D plan draws, projected onto the water
    /// surface so the two views show recognisably the same river.
    private func drawWaves(_ context: GraphicsContext, in bounds: Rect, z: Double, color: Color) {
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
            let point: (Double, Double) -> CGPoint = { along, offset in
                horizontal
                    ? self.screen(Point(x: along, y: across + offset), z: z)
                    : self.screen(Point(x: across + offset, y: along), z: z)
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
        context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1)
    }

    /// Sand-coloured paths with pebbles in them, and timber fences. Both are
    /// drawn in their own materials rather than in the plan's category greys:
    /// on the flat plan a path is a line that means "access", but in a view
    /// of the place it is gravel, and the references are unanimous that the
    /// warm path against the green is half of what makes the scene read.
    private func drawFlatFeatures(_ context: GraphicsContext) {
        for pathEntity in variant.paths {
            var line = Path()
            line.addLines(pathEntity.points.map { screen($0, z: 0.03) })
            let width = max(1.5, CGFloat(pathEntity.widthM * viewport.scale * 0.9))
            // A darker edge under a lighter surface: the path gets a kerb and
            // stops being a stripe painted on the grass.
            context.stroke(
                line,
                with: .color(Self.pathEdge),
                style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                line,
                with: .color(Self.path),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        }
        drawPebbles(context)

        let painter = AxoPainter(context: context, project: { point, z in self.screen(point, z: z) }, scale: viewport.scale)
        for fence in variant.fences {
            AxoKit.fence(painter, points: fence.points, height: 1.3, color: Self.timber)
        }
    }

    private static let path = Color(hex: 0xe8d9b0)
    private static let pathEdge = Color(hex: 0xc4b083)
    private static let timber = Color(hex: 0xa9793f)

    /// Speckle along the paths, only once they are wide enough on screen for
    /// a pebble to be a pebble rather than a stray pixel.
    private func drawPebbles(_ context: GraphicsContext) {
        guard viewport.scale > 4 else { return }
        var pebbles = Path()
        for pathEntity in variant.paths {
            guard pathEntity.points.count > 1 else { continue }
            for segment in 0..<(pathEntity.points.count - 1) {
                let a = pathEntity.points[segment]
                let b = pathEntity.points[segment + 1]
                let length = distance(a, b)
                let count = min(40, Int(length * 1.1))
                guard count > 0 else { continue }
                for index in 0..<count {
                    let seed = "pebble\(segment)"
                    let t = (Double(index) + 0.5) / Double(count)
                    let sideways = AxoNoise.jitter(seed, index, 1, pathEntity.widthM * 0.34)
                    // Perpendicular offset in world space, so pebbles sit
                    // across the path rather than along its centre line.
                    let dx = b.x - a.x, dy = b.y - a.y
                    let norm = (dx * dx + dy * dy).squareRoot()
                    guard norm > 0 else { continue }
                    let point = Point(
                        x: a.x + dx * t - dy / norm * sideways,
                        y: a.y + dy * t + dx / norm * sideways
                    )
                    let centre = screen(point, z: 0.04)
                    let size = CGFloat((0.07 + AxoNoise.value(seed, index, 2) * 0.09) * viewport.scale)
                    pebbles.addEllipse(in: CGRect(x: centre.x - size, y: centre.y - size * 0.7, width: size * 2, height: size * 1.4))
                }
            }
        }
        context.fill(pebbles, with: .color(Self.pathEdge.opacity(0.8)))
    }

    /// Every object's shadow, in one pass under all the massing. One pass
    /// rather than per-object, because a shadow drawn just before its own
    /// building would be painted over by the next building's walls — and
    /// because a single blurred layer costs one filter for the whole scene
    /// instead of one per object.
    ///
    /// The shape is the footprint plus the same footprint slid along the
    /// light, with the span between them filled: the shadow a box casts. All
    /// of it goes into one `Path` and gets one fill, so the overlaps don't
    /// stack up into a darker blob where two parts meet.
    private func drawShadows(_ context: GraphicsContext) {
        guard viewport.scale > 0.8 else { return }
        var shadow = Path()
        var any = false

        for object in variant.objects {
            guard object.metadata["roofMounted"]?.boolValue != true else { continue }
            let height = Massing.shadowHeight(for: object)
            guard height > 0.15 else { continue }
            let corners = object.transform.corners
            guard corners.count == 4 else { continue }
            let offset = AxoLight.shadowOffset(height: height)
            let cast = corners.map { Point(x: $0.x + offset.x, y: $0.y + offset.y) }
            any = true

            shadow.addLines(corners.map { screen($0) })
            shadow.closeSubpath()
            shadow.addLines(cast.map { screen($0) })
            shadow.closeSubpath()
            for index in 0..<4 {
                let next = (index + 1) % 4
                shadow.addLines([
                    screen(corners[index]), screen(corners[next]),
                    screen(cast[next]), screen(cast[index]),
                ])
                shadow.closeSubpath()
            }
        }
        guard any else { return }

        context.drawLayer { layer in
            // Soft edges at usable zooms; at a distance the blur costs more
            // than it shows and a crisp shadow is fine.
            if viewport.scale > 2 {
                layer.addFilter(.blur(radius: max(1.5, CGFloat(viewport.scale * 0.22))))
            }
            layer.fill(shadow, with: .color(.black.opacity(0.22)), style: FillStyle(eoFill: false))
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
            let style = CategoryStyle.of(object.category, daylight)
            let base = Massing.baseElevation(for: object, among: variant.objects)
            let corners = object.transform.corners
            let selected = object.id == selectedObjectID
            let painter = AxoPainter(context: context, project: { point, z in self.screen(point, z: z) }, scale: viewport.scale)
            let roofTones = Massing.roofColor(for: object)
            let roof = Color(hex: roofTones.light)

            // Under the massing rather than over it: a halo on the ground
            // reads as "this patch of the plot", and doesn't paint over the
            // building it is pointing at.
            if highlightedObjectIDs.contains(object.id) {
                var halo = Path()
                halo.addLines(corners.map { self.screen($0, z: base) })
                halo.closeSubpath()
                context.stroke(halo, with: .color(.orange.opacity(0.45)), lineWidth: 9)
                context.stroke(halo, with: .color(.orange), lineWidth: 2)
            }

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
                    glazed: false,
                    surfaces: Massing.surfaces(for: object)
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
                    glazed: true,
                    surfaces: Massing.surfaces(for: object)
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
        // A grove where every tree is identical reads as wallpaper, so each
        // gets its own seed, a little jitter off the grid, and its own size.
        for (index, position) in positions.sorted(by: { $0.x + $0.y < $1.x + $1.y }).enumerated() {
            let seed = object.id + "-\(index)"
            let jittered = Point(
                x: position.x + AxoNoise.jitter(seed, index, 1, 0.55),
                y: position.y + AxoNoise.jitter(seed, index, 2, 0.55)
            )
            let vary = 0.84 + AxoNoise.value(seed, index, 3) * 0.32
            AxoKit.tree(
                painter,
                at: jittered,
                height: height * vary,
                radius: radius * vary,
                conifer: conifer,
                foliage: style.fill,
                outline: style.stroke,
                seed: seed
            )
        }
    }

    private func drawWalls(_ context: GraphicsContext, corners: [Point], from base: Double, to top: Double, style: CategoryStyle) {
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            var face = Path()
            face.addLines([screen(a, z: base), screen(b, z: base), screen(b, z: top), screen(a, z: top)])
            face.closeSubpath()

            // Tone from the scene's own sun, so a block agrees with the
            // gabled buildings around it about which side is lit.
            let shade = AxoLight.shade(normal: AxoLight.wallNormal(from: a, to: b))
            context.fill(face, with: .color(style.fill))
            if shade > 0 { context.fill(face, with: .color(.black.opacity(shade))) }
            if shade < 0 { context.fill(face, with: .color(.white.opacity(-shade))) }
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
        // A top face is the brightest thing on any object: it is the one
        // pointing at the sky.
        let shade = AxoLight.shade(normal: AxoLight.up) - lit
        if shade < 0 { context.fill(face, with: .color(.white.opacity(min(0.35, -shade)))) }
        context.stroke(face, with: .color(style.stroke), lineWidth: selected ? 2.2 : 0.9)
        if selected {
            context.stroke(face, with: .color(.accentColor), lineWidth: 2.2)
        }

        // The plan glyph, laid onto this horizontal face. This is what the
        // projection-agnostic GlyphFrame is for: the panel grid belongs on
        // the roof-mounted array, the table and chairs on the patio, and an
        // affine map of the ground plane is exactly what the glyphs were
        // written against.
        ObjectGlyphs.draw(context, object: object, frame: frame(for: object, at: z), stroke: style.stroke)
        drawSymbol(context, object: object, at: z, style: style)
    }

    /// Maps an object's local metres onto the horizontal plane at `z`.
    /// Horizontal unit vectors keep their length under this projection —
    /// (1,0) lands at (cos 30°, sin 30°), which is still unit length — so the
    /// viewport's own scale carries across unchanged.
    private func frame(for object: PlanObject, at z: Double) -> GlyphFrame {
        let centre = object.transform.center
        let rotation = object.transform.rotationDeg * .pi / 180
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return GlyphFrame(
            project: { localX, localY in
                let world = Point(
                    x: centre.x + localX * cosR - localY * sinR,
                    y: centre.y + localX * sinR + localY * cosR
                )
                return self.screen(world, z: z)
            },
            scale: viewport.scale
        )
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
