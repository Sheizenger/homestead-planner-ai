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
// `Axonometry` is gone: it was a camera with its angles written into the
// arithmetic. `Camera3D` is the same thing with the angles as parameters, and
// `Camera3DTests` pins that the defaults reproduce it exactly.

struct AxonometricPlanView: View {
    let plot: Plot
    let variant: Variant
    @Binding var viewport: Viewport
    @Binding var selectedObjectID: String?
    /// See `PlanCanvasView` — the objects a selected warning is about.
    var highlightedObjectIDs: Set<String> = []
    var showsDimensions: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var cameraYaw: Double = Camera3D.isometricYaw
    @State private var cameraPitch: Double = Camera3D.isometricPitch
    /// Where the camera was when the current orbit began. The drag reads
    /// absolute translation rather than accumulating per-frame deltas, so a
    /// dropped or coalesced event can't leave the camera drifted from where
    /// the cursor says it should be.
    @State private var yawAnchor: Double = Camera3D.isometricYaw
    @State private var pitchAnchor: Double = Camera3D.isometricPitch
    @State private var dragAnchor: CGSize = .zero
    @State private var dragKind: DragKind?
    @State private var magnifyAnchor: CGFloat = 1
    /// Held modifiers, sampled by the view rather than read off the drag:
    /// `DragGesture.Value` doesn't carry them.
    @State private var orbitModifierHeld = false

    /// A drag is one thing or the other for its whole length, decided from
    /// where it started. Deciding per-frame would let a pan turn into an
    /// orbit halfway through if the user happened to press ⌥ mid-drag.
    private enum DragKind { case pan, orbit }

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
                        let kind = dragKind ?? beginDrag(at: value.startLocation, in: geometry.size)
                        switch kind {
                        case .pan:
                            let delta = CGSize(
                                width: value.translation.width - dragAnchor.width,
                                height: value.translation.height - dragAnchor.height
                            )
                            dragAnchor = value.translation
                            viewport.pan(byScreen: Point(x: Double(delta.width), y: Double(delta.height)))
                        case .orbit:
                            orbit(by: value.translation)
                        }
                    }
                    .onEnded { value in
                        let kind = dragKind
                        dragAnchor = .zero
                        dragKind = nil
                        let moved = abs(value.translation.width) + abs(value.translation.height)
                        guard moved < 4 else { return }
                        // A click, not a drag. On the compass that means the
                        // map-app gesture — put north back where it was; the
                        // compass is not over the plan, so nothing there is
                        // selectable anyway.
                        if kind == .orbit, isOnCompass(value.location, in: geometry.size) {
                            resetCamera()
                        } else if kind == .pan {
                            selectedObjectID = objectID(at: value.location)
                        }
                    }
            )
            .onModifierKeysChanged(mask: .option) { _, held in
                orbitModifierHeld = held.contains(.option)
            }
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
        let projected = plot.boundary.map { camera.project($0) }
        // Tall buildings stand up out of the plot's own footprint, so the
        // framed box is padded upward rather than fitted to the ground alone.
        guard var bounds = Rect(bounding: projected) else { return }
        // Padded up for tall buildings and down for the thickness of the
        // block of land, so neither gets cropped by fit-to-plot.
        bounds = Rect(minX: bounds.minX, minY: bounds.minY - 8, maxX: bounds.maxX, maxY: bounds.maxY + Self.slabDepth)
        viewport.fit(bounds, in: Size(width: Double(size.width), height: Double(size.height)), padding: 36)
    }

    /// The camera the whole view is drawn through. Yaw is state so it can be
    /// turned; pitch stays at the isometric elevation, which is what keeps the
    /// plan readable as a plan.
    private var camera: Camera3D { Camera3D(yaw: cameraYaw, pitch: cameraPitch) }

    /// The scene's light, which travels with the camera — see `SceneLight`.
    /// A fixed compass sun leaves half of the orbit unlit, measured.
    private var light: SceneLight { SceneLight.following(camera) }

    // MARK: - Orbit

    /// Radians per point of drag. A full turn takes a little over half a
    /// canvas width across, and the whole usable range of elevation about a
    /// third of its height — enough that a deliberate drag reaches any angle
    /// without the view spinning away from a twitch.
    private static let yawPerPoint = 2 * Double.pi / 640
    private static let pitchPerPoint = (Camera3D.maxPitch - Camera3D.minPitch) / 340

    /// Which gesture this drag is, decided once from where it started.
    private func beginDrag(at start: CGPoint, in size: CGSize) -> DragKind {
        let kind: DragKind = (orbitModifierHeld || isOnCompass(start, in: size)) ? .orbit : .pan
        dragKind = kind
        if kind == .orbit {
            yawAnchor = cameraYaw
            pitchAnchor = cameraPitch
        }
        return kind
    }

    private func orbit(by translation: CGSize) {
        let turned = Camera3D(yaw: yawAnchor, pitch: pitchAnchor).turned(
            byYaw: Double(translation.width) * Self.yawPerPoint,
            pitch: Double(translation.height) * Self.pitchPerPoint
        )
        setCamera(turned)
    }

    /// Moves the camera while keeping the site centred where it already is.
    /// Without the pivot the plot swings out of frame within a few degrees
    /// and the gesture becomes a chase; `Viewport.turn` is covered by tests
    /// that run on Linux, which this layer can't.
    private func setCamera(_ new: Camera3D) {
        let old = camera
        cameraYaw = new.yaw
        cameraPitch = new.pitch
        viewport.turn(from: old, to: new, holding: pivot)
    }

    /// What the camera turns around: the middle of the plot, at eye height
    /// for the buildings on it rather than at ground level, so tall objects
    /// don't slide up and down the screen as the elevation changes.
    private var pivot: Point {
        plot.bounds.map { Point(x: $0.midX, y: $0.midY) } ?? Point(x: 0, y: 0)
    }

    private func step(byYaw radians: Double) {
        setCamera(camera.turned(byYaw: radians))
    }

    private func resetCamera() {
        setCamera(Camera3D())
    }

    private func compassCentre(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - 42, y: 44)
    }

    private func isOnCompass(_ point: CGPoint, in size: CGSize) -> Bool {
        let centre = compassCentre(in: size)
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        return (dx * dx + dy * dy).squareRoot() <= Self.compassRadius + 6
    }

    private static let compassRadius: CGFloat = 22

    private func screen(_ world: Point, z: Double = 0) -> CGPoint {
        let point = viewport.toScreen(camera.project(world, z: z))
        return CGPoint(x: point.x, y: point.y)
    }

    /// The chimney belongs to a wing, not to the box the wings are inscribed
    /// in — on the box's centre it would stand in the courtyard.
    private func mainWingObject(_ object: PlanObject, _ wing: Transform) -> PlanObject {
        var part = object
        part.transform = wing
        return part
    }

    private func zoomControls(in size: CGSize) -> some View {
        VStack(spacing: 4) {
            Button { zoom(by: 1.3, in: size) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
            Button { zoom(by: 1 / 1.3, in: size) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { fit(in: size) } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("Fit the plot to the window")

            Divider().frame(width: 26)

            // Discrete steps as well as the drag, because a modifier-drag is
            // not something anyone finds by accident, and because an eighth
            // of a turn is exactly what you want when a building is hiding
            // behind another one.
            Button { step(byYaw: -.pi / 4) } label: { Image(systemName: "rotate.left") }
                .help("Turn the view 45° anticlockwise")
            Button { step(byYaw: .pi / 4) } label: { Image(systemName: "rotate.right") }
                .help("Turn the view 45° clockwise")
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
        // Its own pass, rendered before anything else: the block of land is
        // the backdrop, and sorting it with the buildings standing on it would
        // only ever be a way to get it wrong.
        let scene = AxoScene()
        defer { scene.render(into: context) }
        let painter = AxoPainter(
            context: context,
            project: { point, z in self.screen(point, z: z) },
            scale: viewport.scale,
            scene: scene,
            depthOf: { point, z in self.camera.depthKey(point, z: z) },
            ellipseAxes: { radius in
                let axes = self.camera.horizontalEllipse(radius: radius)
                return (rx: axes.rx * self.viewport.scale, ry: axes.ry * self.viewport.scale)
            },
            facesCamera: { normal in self.camera.faces(normal) },
            light: light
        )

        // Only the edges facing the viewer have a visible cut face; the far
        // ones are hidden behind the slab's own top.
        let centre = footprintCentre(boundary)
        let edges = (0..<boundary.count).map { (boundary[$0], boundary[($0 + 1) % boundary.count]) }
        for edge in edges.sorted(by: { edgeDepth($0) < edgeDepth($1) }) {
            let normal = SceneLight.wallNormal(from: edge.0, to: edge.1, about: centre)
            guard camera.faces(normal) else { continue }
            painter.face(
                [(edge.0, 0), (edge.1, 0), (edge.1, -Self.slabDepth), (edge.0, -Self.slabDepth)],
                fill: Self.soil,
                shade: light.shade(normal: normal),
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

    /// Mean of the vertices — enough to tell inside from outside for a convex
    /// or mildly concave footprint, which is all an outward normal needs.
    /// Nearest point on segment `a`–`b`, to test whether the gate lies on
    /// this particular run of fence rather than another one.
    private func closestPoint(on a: Point, _ b: Point, to point: Point) -> Point {
        Polygon.project(point, onto: a, b)
    }

    private func footprintCentre(_ points: [Point]) -> Point {
        guard !points.isEmpty else { return Point(x: 0, y: 0) }
        let count = Double(points.count)
        return Point(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }

    /// Depth of the midpoint of an edge, for ordering the slab's cut faces.
    /// Was `x + y`, the fixed camera's sort written out by hand — the third
    /// copy of it to survive the sweep, and the reason the plot's own sides
    /// would have stacked wrongly once the view turned.
    private func edgeDepth(_ edge: (Point, Point)) -> Double {
        camera.depthKey(Point(x: (edge.0.x + edge.1.x) / 2, y: (edge.0.y + edge.1.y) / 2))
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
    /// Water that knows what kind of water it is.
    ///
    /// River, lake and pond all drew the identical blue rectangle with a
    /// different word printed in the middle of it. Three things now differ:
    /// the shape of the bank (`WaterfrontModel.shoreline`, in the engine
    /// where it is tested), the colour, and what the surface does. A river
    /// runs, a lake is open and still, a pond is small and green and weedy.
    private func drawWater(_ context: GraphicsContext) {
        guard let waterfront = plot.waterfront,
              let strip = WaterfrontModel.bounds(of: plot),
              let shore = WaterfrontModel.shoreline(of: plot),
              shore.count > 2 else { return }

        let look = WaterLook.of(waterfront.type)
        let surface = -look.depth

        // The bank first: the ground between the planning line and the water,
        // in the material this kind of water leaves behind. Without it the
        // water reads as a hole cut in the lawn.
        if let zone = WaterfrontModel.zone(of: plot), zone.boundary.count > 2 {
            var land = Path()
            land.addLines(zone.boundary.map { screen($0) })
            land.closeSubpath()
            context.fill(land, with: .color(look.bank))
        }

        var basin = Path()
        basin.addLines(shore.map { screen($0, z: surface) })
        basin.closeSubpath()

        // The cut sides, so the water sits *in* the ground rather than on it
        // — the same reason the plot itself is a slab and not an outline.
        // Only the banks turned away from the camera show their face, which
        // is the camera's question to answer, not a fixed rule.
        let middle = footprintCentre(shore)
        for index in shore.indices {
            let a = shore[index]
            let b = shore[(index + 1) % shore.count]
            let normal = SceneLight.wallNormal(from: a, to: b, about: middle)
            guard !camera.faces(normal) else { continue }
            var side = Path()
            side.addLines([screen(a), screen(b), screen(b, z: surface), screen(a, z: surface)])
            side.closeSubpath()
            context.fill(side, with: .color(look.deep.opacity(0.85)))
        }

        // Deep in the middle, shallower at the edge: a flat fill is what made
        // every body of water read as coloured paper.
        context.fill(
            basin,
            with: .radialGradient(
                Gradient(colors: [look.deep, look.shallow]),
                center: screen(Point(x: strip.midX, y: strip.midY), z: surface),
                startRadius: 0,
                endRadius: CGFloat(max(strip.width, strip.height) * viewport.scale * 0.55)
            )
        )
        context.stroke(basin, with: .color(look.deep.opacity(0.8)), lineWidth: 1.2)

        drawWaterSurface(context, waterfront: waterfront, strip: strip, shore: shore, z: surface, look: look)

        context.draw(
            Text(waterfront.type.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(look.deep.opacity(0.9)),
            at: screen(Point(x: strip.midX, y: strip.midY), z: surface)
        )
    }

    /// What the surface of each kind of water does.
    private func drawWaterSurface(
        _ context: GraphicsContext,
        waterfront: Waterfront,
        strip: Rect,
        shore: [Point],
        z: Double,
        look: WaterLook
    ) {
        let horizontal = waterfront.edge == .north || waterfront.edge == .south
        let longLength = horizontal ? strip.width : strip.height
        guard longLength * viewport.scale > 40 else { return }

        switch waterfront.type {
        case .river:
            drawWaves(context, in: strip, z: z, color: look.deep, along: horizontal)
            // Current: a few long streaks down the channel, which is the one
            // thing a river has and the other two do not. Four, and drifting
            // on a slow sine rather than on per-sample noise — noise at every
            // step drew seven scribbles that read as hatching, not as flow.
            var streaks = Path()
            for index in 0..<4 {
                let across = 0.26 + 0.16 * Double(index)
                let phase = AxoNoise.value("current", index, 1) * 2 * .pi
                var points: [CGPoint] = []
                for step in 0...20 {
                    let along = Double(step) / 20
                    let drift = sin(along * 2 * .pi * 1.2 + phase) * 0.045
                    points.append(screen(inStrip(strip, along: along, across: across + drift, horizontal: horizontal), z: z))
                }
                streaks.addLines(points)
            }
            context.stroke(streaks, with: .color(.white.opacity(0.3)), lineWidth: 1.1)

        case .lake:
            // Still water. The first attempt drew long lines down the lake,
            // which is what the river does — the two came out looking like
            // the same water at different saturations. Broken dashes lying
            // *across* the view instead read as glints on a flat surface,
            // and nothing about them suggests anything is moving.
            var glints = Path()
            for index in 0..<26 {
                let along = 0.06 + 0.88 * AxoNoise.value("glint", index, 1)
                let across = 0.12 + 0.6 * AxoNoise.value("glint", index, 2)
                let length = 0.02 + 0.035 * AxoNoise.value("glint", index, 3)
                glints.move(to: screen(inStrip(strip, along: along - length, across: across, horizontal: horizontal), z: z))
                glints.addLine(to: screen(inStrip(strip, along: along + length, across: across, horizontal: horizontal), z: z))
            }
            context.stroke(glints, with: .color(.white.opacity(0.42)), lineWidth: 1.4)
            reeds(context, along: shore, z: z, clumps: 4, color: look.weed)

        case .pond:
            // Small and weedy: lily pads and reeds round the bank. A pond
            // with wave lines on it reads as a small lake.
            guard viewport.scale > 2.2 else {
                reeds(context, along: shore, z: z, clumps: 7, color: look.weed)
                return
            }
            for index in 0..<14 {
                let along = 0.12 + 0.76 * AxoNoise.value("pad", index, 1)
                let across = 0.18 + 0.5 * AxoNoise.value("pad", index, 2)
                let at = inStrip(strip, along: along, across: across, horizontal: horizontal)
                let radius = 0.28 + AxoNoise.value("pad", index, 3) * 0.3
                let axes = camera.horizontalEllipse(radius: radius)
                let centre = screen(at, z: z)
                var pad = Path()
                pad.addEllipse(in: CGRect(
                    x: centre.x - CGFloat(axes.rx * viewport.scale),
                    y: centre.y - CGFloat(axes.ry * viewport.scale),
                    width: CGFloat(axes.rx * viewport.scale * 2),
                    height: CGFloat(axes.ry * viewport.scale * 2)
                ))
                context.fill(pad, with: .color(look.weed.opacity(0.85)))
                context.stroke(pad, with: .color(look.deep.opacity(0.5)), lineWidth: 0.6)
            }
            reeds(context, along: shore, z: z, clumps: 7, color: look.weed)
        }
    }

    /// A point in the water strip, by fraction along the frontage and
    /// fraction across it.
    private func inStrip(_ strip: Rect, along: Double, across: Double, horizontal: Bool) -> Point {
        horizontal
            ? Point(x: strip.minX + strip.width * along, y: strip.minY + strip.height * across)
            : Point(x: strip.minX + strip.width * across, y: strip.minY + strip.height * along)
    }

    /// Reeds along the bank, in clumps.
    ///
    /// The first pass tested every point of the shoreline against a density
    /// and drew a stem wherever it passed, which at 48 samples gave an even
    /// picket fence round the whole waterline — a hairy edge, not planting.
    /// Reeds grow in stands with gaps between them, and the gaps are what
    /// make it read.
    private func reeds(_ context: GraphicsContext, along shore: [Point], z: Double, clumps: Int, color: Color) {
        guard viewport.scale > 2.5, shore.count > 2, clumps > 0 else { return }
        var stems = Path()
        for clump in 0..<clumps {
            // Spread round the shore with a little wander, so the stands are
            // not at regular intervals either.
            let position = (Double(clump) + 0.5) / Double(clumps) + AxoNoise.jitter("clump", clump, 1, 0.06)
            let anchor = Int(min(max(position, 0), 0.999) * Double(shore.count - 1))
            let stalks = 3 + Int(AxoNoise.value("clump", clump, 2) * 4)
            let root = shore[anchor]
            for stalk in 0..<stalks {
                // Scattered around the anchor, not strung along consecutive
                // shoreline samples: at 48 samples over a 44 m frontage those
                // are a metre apart, so a seven-stalk clump came out five
                // metres wide and seven of them closed up into a hedge.
                let point = Point(
                    x: root.x + AxoNoise.jitter("reed", clump * 10 + stalk, 4, 0.5),
                    y: root.y + AxoNoise.jitter("reed", clump * 10 + stalk, 5, 0.5)
                )
                let height = 0.4 + AxoNoise.value("reed", clump * 10 + stalk, 2) * 0.55
                let lean = AxoNoise.jitter("reed", clump * 10 + stalk, 3, 0.16)
                stems.move(to: screen(point, z: z))
                stems.addLine(to: screen(Point(x: point.x + lean, y: point.y + lean * 0.4), z: z + height))
            }
        }
        context.stroke(stems, with: .color(color), lineWidth: 1.3)
    }

    /// Same alternating-bump wave the 2D plan draws, projected onto the water
    /// surface so the two views show recognisably the same river.
    private func drawWaves(_ context: GraphicsContext, in bounds: Rect, z: Double, color: Color, along horizontal: Bool) {
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
        // Fences are not a flat feature: they stand 1.3 m up and have to sort
        // against the buildings, so they are drawn in `drawMassing`.
    }

    private static let path = Color(hex: 0xe8d9b0)
    private static let pathEdge = Color(hex: 0xc4b083)
    private static let timber = Color(hex: 0xa9793f)
    private static let fenceHeight = 1.3

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

            // A grove is many trees, not one crate: shadowing its footprint
            // put a soft rectangle under the whole orchard.
            if case let .canopy(_, radius, _) = Massing.form(for: object) {
                for position in Massing.grovePositions(for: object) {
                    let offset = light.shadowOffset(height: height)
                    let centre = screen(Point(x: position.x + offset.x, y: position.y + offset.y))
                    let rx = CGFloat(camera.horizontalEllipse(radius: radius).rx * viewport.scale)
                    shadow.addEllipse(in: CGRect(x: centre.x - rx, y: centre.y - rx * 0.6, width: rx * 2, height: rx * 1.2))
                    any = true
                }
                continue
            }

            // The footprint, which for the L-shaped house is six points and
            // not four — it casts the shadow of an L.
            let corners = Massing.footprint(for: object)
            guard corners.count >= 3 else { continue }
            let offset = light.shadowOffset(height: height)
            let cast = corners.map { Point(x: $0.x + offset.x, y: $0.y + offset.y) }
            any = true

            shadow.addLines(corners.map { screen($0) })
            shadow.closeSubpath()
            shadow.addLines(cast.map { screen($0) })
            shadow.closeSubpath()
            for index in corners.indices {
                let next = (index + 1) % corners.count
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

    /// One thing to draw, at one depth. Fences belong in this list rather
    /// than in a pass of their own: drawn before all the buildings, a fence
    /// nearer the camera than a building was still painted over by it, and
    /// the run appeared to walk into the wall and stop. Measured first — the
    /// engine routes no fence through a building, so this was never a
    /// geometry problem, only a painting-order one.
    private enum Drawable {
        case object(PlanObject)
        case rail(Point, Point)
        case post(Point)
        case gate(Point, Point)

        /// Where this sits, for the camera to measure the depth of.
        var anchor: Point {
            switch self {
            case let .object(object): return object.transform.center
            case let .rail(a, b): return Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            case let .post(at): return at
            case let .gate(at, _): return at
            }
        }

        var tiebreak: String {
            switch self {
            case let .object(object): return object.id
            case let .rail(a, _): return "rail-\(a.x)-\(a.y)"
            case let .post(at): return "post-\(at.x)-\(at.y)"
            case let .gate(at, _): return "gate-\(at.x)-\(at.y)"
            }
        }
    }

    /// A rail spanning half the plot has one depth for its whole length, so
    /// it would sort wrong against everything it passes. Cutting runs into
    /// short pieces is what makes a painter's algorithm behave.
    private static let railPieceM = 2.0
    /// A gate wide enough for the driveway that runs to it.
    private static let gateWidthM = 3.2

    /// Where the way in is. The engine decides this — the road-facing
    /// boundary edge nearest the house, skipping any waterfront — and both
    /// the driveway and the entrance walk already run to it. This just asks.
    private var gatePoint: Point? {
        guard let house = variant.objects.first(where: { ObjectLibrary.houseTypeIDs.contains($0.typeId) }) else { return nil }
        return PathsAndFences.findGatePoint(
            boundary: plot.boundary,
            houseCenter: house.transform.center,
            waterfrontBounds: WaterfrontModel.bounds(of: plot)
        )
    }

    private func drawables() -> [Drawable] {
        var items: [Drawable] = []
        for object in variant.objects {
            items.append(.object(object))
        }
        let gate = gatePoint
        for fence in variant.fences {
            guard fence.points.count > 1 else { continue }
            // A gated fence gets an opening rather than an unbroken ring with
            // the driveway running into it.
            let opening: Point? = fence.gated ? gate : nil
            for index in 0..<(fence.points.count - 1) {
                let a = fence.points[index]
                let b = fence.points[index + 1]
                let spanX: Double = b.x - a.x
                let spanY: Double = b.y - a.y
                let length: Double = distance(a, b)
                let steps: Double = (length / Self.railPieceM).rounded(.up)
                let pieces: Int = max(1, Int(steps))
                for piece in 0..<pieces {
                    let t0: Double = Double(piece) / Double(pieces)
                    let t1: Double = Double(piece + 1) / Double(pieces)
                    let from = Point(x: a.x + spanX * t0, y: a.y + spanY * t0)
                    let to = Point(x: a.x + spanX * t1, y: a.y + spanY * t1)
                    let middle = Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    if let opening, distance(middle, opening) < Self.gateWidthM / 2 { continue }
                    items.append(.rail(from, to))
                }
                if let opening, distance(opening, closestPoint(on: a, b, to: opening)) < 0.01 {
                    let length = max(0.001, distance(a, b))
                    let direction = Point(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
                    items.append(.gate(opening, direction))
                }
            }
            for post in AxoKit.fencePosts(along: fence.points) {
                if let opening, distance(post, opening) < Self.gateWidthM / 2 { continue }
                items.append(.post(post))
            }
        }
        let camera = self.camera
        return items.sorted { a, b in
            let da = camera.depthKey(a.anchor)
            let db = camera.depthKey(b.anchor)
            if da == db { return a.tiebreak < b.tiebreak }
            return da < db
        }
    }

    /// Back to front: whatever is further from the viewer is drawn first, so
    /// nearer things paint over it.
    private func drawMassing(_ context: GraphicsContext) {
        // Everything that stands up goes into one scene and is sorted against
        // the camera, rather than each routine emitting its own pieces in an
        // order that only works from one angle.
        let scene = AxoScene()
        defer { scene.render(into: context) }
        let painter = AxoPainter(
            context: context,
            project: { point, z in self.screen(point, z: z) },
            scale: viewport.scale,
            scene: scene,
            depthOf: { point, z in self.camera.depthKey(point, z: z) },
            ellipseAxes: { radius in
                let axes = self.camera.horizontalEllipse(radius: radius)
                return (rx: axes.rx * self.viewport.scale, ry: axes.ry * self.viewport.scale)
            },
            facesCamera: { normal in self.camera.faces(normal) },
            light: light
        )

        for item in drawables() {
            switch item {
            case let .rail(a, b):
                AxoKit.fenceRail(painter, from: a, to: b, height: Self.fenceHeight, color: Self.timber)
            case let .post(at):
                AxoKit.fencePost(painter, at: at, height: Self.fenceHeight, color: Self.timber)
            case let .gate(at, direction):
                AxoKit.gate(
                    painter,
                    at: at,
                    along: direction,
                    width: Self.gateWidthM,
                    height: Self.fenceHeight,
                    post: Self.timber.mix(with: .black, by: 0.2),
                    leaf: Self.timber
                )
            case let .object(object):
                draw(object, in: context, painter: painter)
            }
        }
    }

    /// One object, at its own elevation. Split out of the loop above: the
    /// combined body had grown past a hundred lines of switch and closures,
    /// which is a lot to ask of the type checker for no benefit.
    private func draw(_ object: PlanObject, in context: GraphicsContext, painter: AxoPainter) {
        let style = CategoryStyle.of(object.category, daylight)
        let base = Massing.baseElevation(for: object, among: variant.objects)
        let corners = object.transform.corners
        let selected = object.id == selectedObjectID
        // Walls and roof come from the per-type palette, not the
        // category: on this view "a barn" has to be distinguishable from
        // "a coop", which sharing an `animal` fill made impossible.
        let palette = Massing.palette(for: object)
        let roof = Color(hex: palette.roof)
        let wallColor = Color(hex: palette.wall)
        let wallOutline = Color(hex: palette.wall).mix(with: .black, by: 0.32)

        // Under the massing rather than over it: a halo on the ground
        // reads as "this patch of the plot", and doesn't paint over the
        // building it is pointing at.
        if highlightedObjectIDs.contains(object.id) {
            let hull = silhouette(of: object, base: base)
            if hull.count > 2 {
                var halo = Path()
                halo.addLines(hull)
                halo.closeSubpath()
                context.stroke(halo, with: .color(.orange.opacity(0.45)), lineWidth: 9)
                context.stroke(halo, with: .color(.orange), lineWidth: 2)
            }
        }

        switch Massing.form(for: object) {
        case .flat(let height):
            // A slab with visible sides, not a sticker. A patio or a pool
            // painted flat on the grass is the one thing in the scene with
            // no thickness at all, and it reads as a decal among solids.
            if height > 0.04 {
                drawWalls(context, corners: corners, from: base, to: base + height, fill: style.fill, outline: style.stroke)
            }
            drawTopFace(context, corners: corners, z: base + height, style: style, object: object, selected: selected, lit: 0)

        case .block(let height):
            // Painted metal from the palette, not the category fill: the
            // fill is a pale plan tint and left equipment as white cubes.
            drawWalls(context, corners: corners, from: base, to: base + height, fill: wallColor, outline: wallOutline)
            drawTopFace(context, corners: corners, z: base + height, style: style, object: object, selected: selected, lit: 0.10, fill: roof)

        case .gabled(let eaves, let ridge):
            AxoKit.gabledBuilding(
                painter,
                object: object,
                base: base,
                eaves: eaves,
                ridge: ridge,
                wall: wallColor,
                wallOutline: wallOutline,
                roof: roof,
                trim: Color(hex: palette.trim),
                glazed: false,
                walled: !Massing.isOpenSided(object),
                facing: approach(to: object),
                doorway: Massing.doorway(for: object),
                surfaces: Massing.surfaces(for: object)
            )
            if ["house", "house-l", "banya", "smokehouse"].contains(object.typeId) {
                AxoKit.chimney(painter, object: object, base: base, ridgeZ: base + ridge, wall: Color(hex: palette.trim), outline: wallOutline)
            }

        case .ell(let eaves, let ridge):
            // Two wings, each an ordinary gabled building. They butt rather
            // than overlap (see `LShape`), they share an eaves height, and
            // because they are the same depth the common roof pitch puts
            // their ridges at the same height — so the junction reads as one
            // roof with a valley in it rather than two buildings touching.
            let (main, cross) = LShape.wings(of: object.transform)
            let wings = [(main, true), (cross, false)]
                .sorted { camera.depthKey($0.0.center) < camera.depthKey($1.0.center) }
            for (wing, isMain) in wings {
                var part = object
                part.transform = wing
                // Its own id, or both wings draw with the same grain, the
                // same plank offsets and the same shingle scatter.
                part.id = object.id + (isMain ? "-main" : "-cross")
                AxoKit.gabledBuilding(
                    painter,
                    object: part,
                    base: base,
                    eaves: eaves,
                    ridge: ridge,
                    wall: wallColor,
                    wallOutline: wallOutline,
                    roof: roof,
                    trim: Color(hex: palette.trim),
                    glazed: false,
                    walled: true,
                    // One front door, on the range that faces the way in.
                    facing: isMain ? approach(to: object) : nil,
                    doorway: isMain ? .pedestrian : .windows,
                    surfaces: Massing.surfaces(for: object)
                )
            }
            AxoKit.chimney(painter, object: mainWingObject(object, main), base: base, ridgeZ: base + ridge, wall: Color(hex: palette.trim), outline: wallOutline)

        case .gambrel(let eaves, let knuckle, let ridge):
            AxoKit.gambrelBuilding(
                painter,
                object: object,
                base: base,
                eaves: eaves,
                knuckle: knuckle,
                ridge: ridge,
                wall: wallColor,
                wallOutline: wallOutline,
                roof: roof,
                trim: Color(hex: palette.trim),
                facing: approach(to: object),
                surfaces: Massing.surfaces(for: object)
            )

        case .glass(let eaves, let ridge):
            AxoKit.gabledBuilding(
                painter,
                object: object,
                base: base,
                eaves: eaves,
                ridge: ridge,
                // Thin enough to see the rows through, which is the point
                // of drawing them.
                wall: wallColor.opacity(0.35),
                wallOutline: Color(hex: palette.trim),
                roof: Color(hex: 0xbfe3e8).opacity(0.55),
                trim: Color(hex: palette.trim),
                glazed: true,
                surfaces: Massing.surfaces(for: object)
            )

        case .cylinder(let height, let radiusScale):
            let radius = min(object.transform.width, object.transform.height) * radiusScale
            painter.cylinder(
                center: object.transform.center,
                radius: radius,
                from: base,
                to: base + height,
                fill: wallColor,
                outline: wallOutline,
                shade: 0.22,
                cap: Self.cylinderCap(for: object)
            )

        case .rows:
            AxoKit.plantedRows(
                painter,
                object: object,
                base: base,
                crop: Color(hex: Massing.foliage(for: object)),
                outline: style.stroke
            )

        case .canopy(let height, let radius, let conifer):
            drawOrchard(painter, object: object, height: height, radius: radius, conifer: conifer, style: style)

        case .basin:
            AxoKit.pool(painter, object: object, base: base, coping: Color(hex: 0xe6e0d2))

        case .deck:
            AxoKit.dock(painter, object: object, base: base, deck: Color(hex: 0xb08a5c))

        case .paved:
            AxoKit.patio(painter, object: object, base: base, paving: Color(hex: 0xd8d2c6))

        case let .cabinet(height, kind):
            AxoKit.cabinet(
                painter,
                object: object,
                base: base,
                height: height,
                wall: wallColor,
                roof: roof,
                trim: Color(hex: palette.trim),
                kind: kind,
                facing: approach(to: object)
            )

        case .buried:
            AxoKit.septicField(
                painter,
                object: object,
                base: base,
                mound: Color(hex: 0x6f9c47),
                cover: Color(hex: 0x9aa0a6)
            )

        case .turbine:
            AxoKit.turbine(
                painter,
                object: object,
                base: base,
                housing: Color(hex: palette.wall),
                metal: Color(hex: palette.trim)
            )

        case .panels(let height):
            AxoKit.solarPanels(
                painter,
                object: object,
                base: base,
                height: height,
                panel: Color(hex: 0x2c3f66),
                frame: Color(hex: 0xb9c3cc)
            )
        }

        if selected { outlineSilhouette(context, object: object, base: base) }
        if showsDimensions { drawDimensions(context, for: object, z: base) }
    }

    /// A drum, a silo or a wellhead. Same cylinder, three silhouettes, and
    /// that is enough to tell them apart across the plot without a label.
    private static func cylinderCap(for object: PlanObject) -> AxoPainter.Cap {
        switch object.typeId {
        case "water-tank", "rainwater-cistern": return .dome
        case "well": return .cone
        default: return .flat
        }
    }

    /// The nearest point of the path network to this building — what serves
    /// it, and therefore which wall its door belongs on. A garage with a
    /// driveway arriving at the back had its door on a blank elevation
    /// facing a fence.
    private func approach(to object: PlanObject) -> Point? {
        let centre = object.transform.center

        // A garage faces the gate. A car arrives from the road and leaves
        // toward it, so the one wall its door can be on is the one looking
        // that way — the nearest point of the path network is not the same
        // thing and can easily be a node beside or behind the building,
        // which is how the door ended up on a blank elevation again.
        if Massing.doorway(for: object) == .vehicle, let gate = gatePoint {
            return gate
        }

        var best: Point?
        var bestDistance = Double.infinity
        for path in variant.paths {
            for point in path.points {
                let d = distance(point, centre)
                if d < bestDistance {
                    bestDistance = d
                    best = point
                }
            }
        }
        return best
    }

    /// The object's outline as drawn, in screen space.
    private func silhouette(of object: PlanObject, base: Double) -> [CGPoint] {
        Silhouette.path(for: object, base: base) { point, z in self.screen(point, z: z) }
    }

    /// The same outline the click is tested against, so what you can select
    /// and what gets ringed are one shape.
    private func outlineSilhouette(_ context: GraphicsContext, object: PlanObject, base: Double) {
        let hull = silhouette(of: object, base: base)
        guard hull.count > 2 else { return }
        var path = Path()
        path.addLines(hull)
        path.closeSubpath()
        context.stroke(path, with: .color(.accentColor.opacity(0.35)), lineWidth: 6)
        context.stroke(path, with: .color(.accentColor), lineWidth: 2)
    }

    /// What the click landed on, tested against each object's drawn silhouette
    /// rather than its footprint. Inverting the projection at ground level,
    /// which is what this used to do, made only the flat diamond under a
    /// building clickable — the walls and roof, which are the whole of what
    /// you can see, missed.
    ///
    /// Front to back, so the object painted on top is the one you get.
    private func objectID(at location: CGPoint) -> String? {
        for item in drawables().reversed() {
            guard case let .object(object) = item else { continue }
            let base = Massing.baseElevation(for: object, among: variant.objects)
            if Silhouette.contains(location, in: silhouette(of: object, base: base)) { return object.id }
        }
        return nil
    }

    private func drawOrchard(_ painter: AxoPainter, object: PlanObject, height: Double, radius: Double, conifer: Bool, style: CategoryStyle) {
        let base = Color(hex: Massing.foliage(for: object))
        // Back to front within the grove, so near trees overlap far ones, and
        // every tree its own seed: a grove where each one is identical reads
        // as wallpaper.
        let grove = Massing.grovePositions(for: object)
            .sorted { camera.depthKey($0) < camera.depthKey($1) }
        for (index, position) in grove.enumerated() {
            let seed = object.id + "-\(index)"
            let jittered = Point(
                x: position.x + AxoNoise.jitter(seed, index, 1, 0.55),
                y: position.y + AxoNoise.jitter(seed, index, 2, 0.55)
            )
            let vary = 0.84 + AxoNoise.value(seed, index, 3) * 0.32
            // A little tonal drift tree to tree, the way a real row of them
            // is never one flat green.
            let tint = AxoNoise.value(seed, index, 4)
            let foliage = tint > 0.5
                ? base.mix(with: Color(hex: 0x2f6b46), by: (tint - 0.5) * 0.5)
                : base.mix(with: Color(hex: 0x8dc63f), by: (0.5 - tint) * 0.5)
            AxoKit.tree(
                painter,
                at: jittered,
                height: height * vary,
                radius: radius * vary,
                conifer: conifer,
                foliage: foliage,
                outline: style.stroke,
                seed: seed
            )
        }
    }

    private func drawWalls(_ context: GraphicsContext, corners: [Point], from base: Double, to top: Double, fill: Color, outline: Color) {
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            var face = Path()
            face.addLines([screen(a, z: base), screen(b, z: base), screen(b, z: top), screen(a, z: top)])
            face.closeSubpath()

            // Tone from the scene's own sun, so a block agrees with the
            // gabled buildings around it about which side is lit.
            let shade = light.shade(normal: SceneLight.wallNormal(from: a, to: b, about: footprintCentre(corners)))
            context.fill(face, with: .color(fill))
            if shade > 0 { context.fill(face, with: .color(.black.opacity(shade))) }
            if shade < 0 { context.fill(face, with: .color(.white.opacity(-shade))) }
            context.stroke(face, with: .color(outline.opacity(0.8)), lineWidth: 0.8)
        }
    }

    private func drawTopFace(
        _ context: GraphicsContext,
        corners: [Point],
        z: Double,
        style: CategoryStyle,
        object: PlanObject,
        selected: Bool,
        lit: Double,
        fill: Color? = nil
    ) {
        var face = Path()
        face.addLines(corners.map { screen($0, z: z) })
        face.closeSubpath()
        context.fill(face, with: .color(fill ?? style.fill))
        // A top face is the brightest thing on any object: it is the one
        // pointing at the sky.
        let shade = light.shade(normal: SceneLight.up) - lit
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

    /// The compass, which is also the rotation control: a dial you can grab.
    ///
    /// A modifier-drag is invisible, and a pair of step buttons only gets you
    /// to eight angles. Every map app puts the free rotation on the compass
    /// and resets the bearing when you click it, so that is what this does —
    /// and it has the advantage that the thing you are turning is the thing
    /// that shows you which way you are facing.
    private func drawCompass(_ context: GraphicsContext, size: CGSize) {
        let centre = compassCentre(in: size)
        let radius = Self.compassRadius
        let turned = !camera.isIsometric

        // North runs along -y in world space; project it to get its screen
        // direction under this rotation, so the arrow matches the drawing.
        let origin = camera.project(x: 0, y: 0, z: 0)
        let north = camera.project(x: 0, y: -1, z: 0)
        let dx = north.x - origin.x
        let dy = north.y - origin.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }

        // A dial to aim at. Faint at the default view so it stays furniture,
        // and firmer once the camera has been turned, when it doubles as the
        // "click to put north back" affordance.
        let dial = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.fill(dial, with: .color(chrome.furniture.opacity(turned ? 0.10 : 0.05)))
        context.stroke(dial, with: .color(chrome.furniture.opacity(turned ? 0.55 : 0.28)), lineWidth: 1)

        // Ticks at the eight steps the buttons move in, so a turned view
        // reads as turned by a definite amount rather than just crooked.
        for step in 0..<8 {
            let angle = Double(step) / 8 * 2 * .pi
            let unit = camera.project(x: sin(angle), y: -cos(angle), z: 0)
            let tickLength = (unit.x * unit.x + unit.y * unit.y).squareRoot()
            guard tickLength > 0 else { continue }
            let ux = unit.x / tickLength
            let uy = unit.y / tickLength
            var tick = Path()
            tick.move(to: CGPoint(x: centre.x + CGFloat(ux) * (radius - 4), y: centre.y + CGFloat(uy) * (radius - 4)))
            tick.addLine(to: CGPoint(x: centre.x + CGFloat(ux) * (radius - 1), y: centre.y + CGFloat(uy) * (radius - 1)))
            context.stroke(tick, with: .color(chrome.furniture.opacity(0.35)), lineWidth: 1)
        }

        let reach = radius - 6
        let tip = CGPoint(x: centre.x + CGFloat(dx / length) * reach, y: centre.y + CGFloat(dy / length) * reach)
        let tail = CGPoint(x: centre.x - CGFloat(dx / length) * reach * 0.7, y: centre.y - CGFloat(dy / length) * reach * 0.7)

        // A needle rather than a bare line: the head reads as a direction at
        // a glance where a stick needs the N to disambiguate it.
        let sideX = CGFloat(-dy / length) * 4.5
        let sideY = CGFloat(dx / length) * 4.5
        var needle = Path()
        needle.move(to: tip)
        needle.addLine(to: CGPoint(x: centre.x + sideX, y: centre.y + sideY))
        needle.addLine(to: CGPoint(x: centre.x - sideX, y: centre.y - sideY))
        needle.closeSubpath()
        context.fill(needle, with: .color(chrome.furniture))

        var shaft = Path()
        shaft.move(to: centre)
        shaft.addLine(to: tail)
        context.stroke(shaft, with: .color(chrome.furniture.opacity(0.45)), lineWidth: 1.5)

        context.draw(
            Text("N").font(.system(size: 9, weight: .semibold)).foregroundColor(chrome.furniture),
            at: CGPoint(x: centre.x + CGFloat(dx / length) * (radius + 8), y: centre.y + CGFloat(dy / length) * (radius + 8))
        )
    }
}
