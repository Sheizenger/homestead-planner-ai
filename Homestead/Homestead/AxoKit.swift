//
//  AxoKit.swift
//  Homestead
//
//  The kit of parts the axonometric view builds objects from: pitched roofs
//  with gable ends, doors, windows, chimneys, cylinders, conifers, planted
//  rows. Extruded boxes read as abstract massing; these read as buildings,
//  which is the whole point of showing height at all.
//
//  Everything is expressed in world metres plus an elevation, and projected
//  through one closure, so the kit knows nothing about the projection or the
//  viewport it is being drawn into.
//

import SwiftUI
import HomesteadEngine

/// Everything the kit draws, held until the whole scene has been described.
///
/// The kit used to draw straight into the context, which forced the draw order
/// to *be* the depth order: each routine emitted its own faces far-to-near by
/// hand, using `x + y`. That is a camera written into a hundred call sites,
/// and it is why the view could not turn. Collecting instead lets one pass
/// sort everything against the actual camera, and leaves all hundred call
/// sites exactly as they were.
final class AxoScene {
    struct Item {
        let depth: Double
        /// Emission index, so a tie keeps the order the kit intended — a
        /// fascia emitted just after its roof plane stays just after it.
        let order: Int
        let draw: (GraphicsContext) -> Void
    }

    private(set) var items: [Item] = []

    func add(depth: Double, draw: @escaping (GraphicsContext) -> Void) {
        items.append(Item(depth: depth, order: items.count, draw: draw))
    }

    /// Far to near.
    func render(into context: GraphicsContext) {
        for item in items.sorted(by: { $0.depth == $1.depth ? $0.order < $1.order : $0.depth < $1.depth }) {
            item.draw(context)
        }
    }
}

/// A little buffer of drawing, so a routine that builds its own paths can hand
/// them to the scene as one piece at one depth instead of painting straight
/// into the context. Trees, crops, the pool, the patio and the turbine all
/// build ellipses and curves directly; without this they would be drawn in
/// call order and would not sort against anything.
struct AxoOps {
    private var ops: [(path: Path, color: Color, width: CGFloat, isFill: Bool)] = []

    mutating func fill(_ path: Path, with color: Color) {
        ops.append((path, color, 0, true))
    }

    mutating func stroke(_ path: Path, with color: Color, lineWidth: CGFloat) {
        ops.append((path, color, lineWidth, false))
    }

    func emit(into painter: AxoPainter, at anchor: Point, z: Double) {
        guard !ops.isEmpty else { return }
        let collected = ops
        painter.sprite(at: anchor, z: z) { context in
            for op in collected {
                if op.isFill {
                    context.fill(op.path, with: .color(op.color))
                } else {
                    context.stroke(op.path, with: .color(op.color), lineWidth: op.width)
                }
            }
        }
    }
}

struct AxoPainter {
    /// Only for routines that still draw immediately into a scene of their
    /// own; everything in the kit goes through `scene`.
    let context: GraphicsContext
    /// World point at elevation z → screen.
    let project: (Point, Double) -> CGPoint
    let scale: Double
    /// Where drawing is collected, and the camera the depth is measured
    /// against. Both are supplied by the view.
    let scene: AxoScene
    let depthOf: (Point, Double) -> Double
    /// Screen semi-axes of a horizontal circle of `radius` metres. A horizontal
    /// circle projects to an axis-aligned ellipse at any yaw — full width
    /// across, foreshortened by the camera's pitch — so a tank lid stays an
    /// ellipse however far the view is turned. The kit used to spell this
    /// `r * 1.414 * cos30` and `r * 1.414 * sin30`, which is this for one
    /// camera; `Camera3DTests` pins that they agree at the default.
    let ellipseAxes: (Double) -> (rx: Double, ry: Double)
    /// True when a face with this outward normal is turned toward the camera.
    /// Every routine here used to ask `normal.x + normal.y > 0`, which is this
    /// question answered for one fixed camera — ten copies of it, and the main
    /// reason the view could not be turned.
    let facesCamera: ((x: Double, y: Double, z: Double)) -> Bool
    /// The scene's one light. It travels with the camera, so it has to come
    /// in with the camera rather than being a global the kit reaches for.
    let light: SceneLight

    /// Hands a piece of drawing to the scene at the depth of one world point —
    /// for the ellipses and glyphs that build their own paths rather than
    /// going through `face`.
    func sprite(at anchor: Point, z: Double, draw: @escaping (GraphicsContext) -> Void) {
        scene.add(depth: depthOf(anchor, z), draw: draw)
    }

    /// Depth of a run of world points, which is what a face or a line sorts by.
    private func depth(of vertices: [(Point, Double)]) -> Double {
        guard !vertices.isEmpty else { return 0 }
        return vertices.reduce(0.0) { $0 + depthOf($1.0, $1.1) } / Double(vertices.count)
    }

    func path(_ vertices: [(Point, Double)]) -> Path {
        var path = Path()
        path.addLines(vertices.map { project($0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    /// `shade` darkens (positive) or lightens (negative) the face, which is
    /// all the lighting model this needs: two wall tones and a brighter roof
    /// are enough to read as solid.
    func face(_ vertices: [(Point, Double)], fill: Color, shade: Double, outline: Color? = nil, lineWidth: CGFloat = 0.7) {
        let shape = path(vertices)
        scene.add(depth: depth(of: vertices)) { context in
            context.fill(shape, with: .color(fill))
            if shade > 0 { context.fill(shape, with: .color(.black.opacity(shade))) }
            if shade < 0 { context.fill(shape, with: .color(.white.opacity(-shade))) }
            if let outline { context.stroke(shape, with: .color(outline), lineWidth: lineWidth) }
        }
    }

    /// A face with a surface on it. The pattern is drawn in the face's own
    /// basis — `u` along the first edge, `v` along the last — so it follows
    /// the projection instead of being pasted flat over it: courses on a
    /// gable end stay level, ribs on a roof plane run up the pitch. A
    /// triangle is a quad with two corners in the same place, which keeps
    /// gable ends on the same code path.
    func face(
        _ vertices: [(Point, Double)],
        fill: Color,
        shade: Double,
        outline: Color? = nil,
        lineWidth: CGFloat = 0.7,
        material: AxoMaterial,
        seed: String = ""
    ) {
        face(vertices, fill: fill, shade: shade, outline: outline, lineWidth: lineWidth)
        texture(vertices, material: material, seed: seed)
    }

    /// Metres between two points in space, for spacing a pattern by real
    /// size rather than by screen size — a barn's planks are the same width
    /// as a shed's.
    private func span(_ a: (Point, Double), _ b: (Point, Double)) -> Double {
        let dx = b.0.x - a.0.x, dy = b.0.y - a.0.y, dz = b.1 - a.1
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    private func blend(_ a: (Point, Double), _ b: (Point, Double), _ t: Double) -> (Point, Double) {
        (Point(x: a.0.x + (b.0.x - a.0.x) * t, y: a.0.y + (b.0.y - a.0.y) * t), a.1 + (b.1 - a.1) * t)
    }

    /// Bilinear point inside the face: `u` along v0→v1, `v` along v0→v3.
    private func at(_ vertices: [(Point, Double)], _ u: Double, _ v: Double) -> (Point, Double) {
        let top = blend(vertices[0], vertices[1], u)
        let bottom = blend(vertices[3], vertices[2], u)
        return blend(top, bottom, v)
    }

    func texture(_ vertices: [(Point, Double)], material: AxoMaterial, seed: String) {
        guard vertices.count == 4, material.pitch > 0 else { return }
        // Collected, not drawn: the pattern belongs to its face and has to
        // travel with it when the scene is sorted against the camera.
        var ops: [(path: Path, color: Color, width: CGFloat, isFill: Bool)] = []
        func stroke(_ path: Path, with shading: Color, lineWidth: CGFloat) {
            ops.append((path, shading, lineWidth, false))
        }
        func fill(_ path: Path, with shading: Color) {
            ops.append((path, shading, 0, true))
        }
        let uSpan = max(span(vertices[0], vertices[1]), span(vertices[3], vertices[2]))
        let vSpan = max(span(vertices[0], vertices[3]), span(vertices[1], vertices[2]))
        guard uSpan > 0, vSpan > 0 else { return }

        // Below a few points per row the pattern turns into grey mush that
        // costs paths and reads as noise — better to show the clean face.
        let rowPixels = material.pitch * scale
        guard rowPixels > 3.5 else { return }
        let rows = min(60, Int(vSpan / material.pitch))
        let columns = min(60, Int(uSpan / material.pitch))
        guard rows >= 1 || columns >= 1 else { return }

        let ink = Color.black.opacity(material == .glass ? 0.12 : 0.17)
        let lineWidth: CGFloat = 0.6

        switch material {
        case .plank, .brick, .shingle, .thatch:
            for row in 1...max(1, rows) {
                let v = Double(row) / Double(max(1, rows) + 1)
                var path = Path()
                path.move(to: project(at(vertices, 0, v).0, at(vertices, 0, v).1))
                // Thatch sags between the rafters; a straight line reads as
                // corrugated iron instead.
                if material == .thatch {
                    for step in 1...6 {
                        let u = Double(step) / 6
                        let wobble = AxoNoise.jitter(seed, row, step, 0.012)
                        let point = at(vertices, u, min(0.98, max(0.02, v + wobble)))
                        path.addLine(to: project(point.0, point.1))
                    }
                } else {
                    let end = at(vertices, 1, v)
                    path.addLine(to: project(end.0, end.1))
                }
                stroke(path, with: (ink), lineWidth: lineWidth)
            }
        default:
            break
        }

        switch material {
        case .board, .metalRoof:
            for column in 1...max(1, columns) {
                let u = Double(column) / Double(max(1, columns) + 1)
                let top = at(vertices, u, 0), bottom = at(vertices, u, 1)
                var path = Path()
                path.move(to: project(top.0, top.1))
                path.addLine(to: project(bottom.0, bottom.1))
                stroke(path, with: (ink), lineWidth: material == .board ? 0.9 : lineWidth)
            }
        case .brick, .shingle:
            // Staggered joints, which is what separates a brick wall from a
            // stack of horizontal lines.
            guard rowPixels > 6 else { break }
            let perRow = max(2, min(24, Int(uSpan / (material.pitch * (material == .brick ? 2 : 1.4)))))
            for row in 0...max(1, rows) {
                let v0 = Double(row) / Double(max(1, rows) + 1)
                let v1 = Double(row + 1) / Double(max(1, rows) + 1)
                for column in 0...perRow {
                    let offset = row % 2 == 0 ? 0.0 : 0.5
                    let u = (Double(column) + offset) / Double(perRow)
                    guard u > 0.01, u < 0.99 else { continue }
                    let a = at(vertices, u, v0), b = at(vertices, u, min(1, v1))
                    var path = Path()
                    path.move(to: project(a.0, a.1))
                    path.addLine(to: project(b.0, b.1))
                    stroke(path, with: (ink), lineWidth: 0.5)
                }
            }
        case .glass:
            // One diagonal streak: the cue that a surface is reflective, and
            // the reason a greenhouse reads as glazed rather than white.
            var streak = Path()
            let a = at(vertices, 0.12, 0.92), b = at(vertices, 0.58, 0.08)
            let c = at(vertices, 0.78, 0.08), d = at(vertices, 0.32, 0.92)
            streak.move(to: project(a.0, a.1))
            streak.addLine(to: project(b.0, b.1))
            streak.addLine(to: project(c.0, c.1))
            streak.addLine(to: project(d.0, d.1))
            streak.closeSubpath()
            fill(streak, with: (.white.opacity(0.16)))
        default:
            break
        }

        guard !ops.isEmpty else { return }
        let collected = ops
        scene.add(depth: depth(of: vertices)) { context in
            for op in collected {
                if op.isFill {
                    context.fill(op.path, with: .color(op.color))
                } else {
                    context.stroke(op.path, with: .color(op.color), lineWidth: op.width)
                }
            }
        }
    }

    func line(_ a: (Point, Double), _ b: (Point, Double), color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: project(a.0, a.1))
        path.addLine(to: project(b.0, b.1))
        scene.add(depth: depth(of: [a, b])) { context in
            context.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    /// What sits on top of a cylinder. A flat disc is a drum; a dome is a
    /// silo and a little cone is a wellhead, and telling those apart at a
    /// glance is free once the shape does the work.
    enum Cap {
        case flat, dome, cone
    }

    /// A horizontal circle projects to a screen-axis-aligned ellipse under
    /// this projection, so a cylinder is two ellipses plus the strip between
    /// their tangents.
    func cylinder(center: Point, radius: Double, from: Double, to: Double, fill: Color, outline: Color, shade: Double, cap: Cap = .flat) {
        let rx = CGFloat(ellipseAxes(radius).rx)
        let ry = CGFloat(ellipseAxes(radius).ry)
        guard rx > 1 else { return }
        var ops = AxoOps()
        defer { ops.emit(into: self, at: center, z: (from + to) / 2) }

        let bottom = project(center, from)
        let top = project(center, to)

        var body = Path()
        body.move(to: CGPoint(x: bottom.x - rx, y: bottom.y))
        body.addLine(to: CGPoint(x: top.x - rx, y: top.y))
        body.addLine(to: CGPoint(x: top.x + rx, y: top.y))
        body.addLine(to: CGPoint(x: bottom.x + rx, y: bottom.y))
        body.closeSubpath()
        ops.fill(body, with: (fill))
        ops.fill(body, with: (.black.opacity(shade)))

        let bottomCap = Path(ellipseIn: CGRect(x: bottom.x - rx, y: bottom.y - ry, width: rx * 2, height: ry * 2))
        ops.fill(bottomCap, with: (fill))
        ops.fill(bottomCap, with: (.black.opacity(shade)))

        let topCap = Path(ellipseIn: CGRect(x: top.x - rx, y: top.y - ry, width: rx * 2, height: ry * 2))
        ops.fill(topCap, with: (fill))
        ops.fill(topCap, with: (.white.opacity(0.12)))
        ops.stroke(topCap, with: (outline), lineWidth: 0.8)
        ops.stroke(body, with: (outline), lineWidth: 0.8)

        switch cap {
        case .flat:
            break
        case .dome, .cone:
            let apexHeight = radius * (cap == .dome ? 0.85 : 1.2)
            let apex = project(center, to + apexHeight)
            var shell = Path()
            shell.move(to: CGPoint(x: top.x - rx, y: top.y))
            if cap == .dome {
                shell.addQuadCurve(to: apex, control: CGPoint(x: top.x - rx, y: apex.y + ry * 0.4))
                shell.addQuadCurve(to: CGPoint(x: top.x + rx, y: top.y), control: CGPoint(x: top.x + rx, y: apex.y + ry * 0.4))
            } else {
                shell.addLine(to: apex)
                shell.addLine(to: CGPoint(x: top.x + rx, y: top.y))
            }
            shell.addCurve(
                to: CGPoint(x: top.x - rx, y: top.y),
                control1: CGPoint(x: top.x + rx * 0.55, y: top.y + ry * 1.15),
                control2: CGPoint(x: top.x - rx * 0.55, y: top.y + ry * 1.15)
            )
            shell.closeSubpath()
            ops.fill(shell, with: (fill))
            ops.fill(shell, with: (.white.opacity(0.10)))
            ops.stroke(shell, with: (outline), lineWidth: 0.8)
        }
    }
}

enum AxoKit {
    /// Midpoint of two world points.
    private static func mid(_ a: Point, _ b: Point) -> Point {
        Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Moves `point` toward `other` by `fraction` of the way.
    private static func lerp(_ point: Point, _ other: Point, _ fraction: Double) -> Point {
        Point(x: point.x + (other.x - point.x) * fraction, y: point.y + (other.y - point.y) * fraction)
    }

    /// Walls to the eaves, gable triangles above them on the short ends, and
    /// two roof planes meeting at a ridge along the long axis — the shape
    /// every house in the references is built from.
    static func gabledBuilding(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        eaves: Double,
        ridge: Double,
        wall: Color,
        wallOutline: Color,
        roof: Color,
        trim: Color,
        glazed: Bool,
        // False for an open-sided pavilion: posts hold the roof up and there
        // is nothing to put a door in. One flag reuses the whole roof rather
        // than duplicating it — the roof is the only part a gazebo shares
        // with a shed.
        walled: Bool = true,
        /// What serves this building — the nearest point of the path network.
        /// The door goes on the wall that looks at it.
        facing: Point? = nil,
        doorway: Doorway = .pedestrian,
        surfaces: Massing.Surfaces
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }

        let eavesZ = base + eaves
        let ridgeZ = base + ridge
        let alongX = object.transform.width >= object.transform.height

        // Under the glass, before the shell goes over it. A greenhouse that
        // is an empty glass box is a bus shelter; in every reference you can
        // see the rows through the glazing, and that is what names it.
        if glazed { greenhouseInterior(painter, object: object, base: base, alongX: alongX) }

        // Ridge runs down the middle of the longer axis; the two short ends
        // carry the gables.
        let (ridgeA, ridgeB, longEdges, gableEnds): (Point, Point, [(Point, Point)], [(Point, Point)]) = alongX
            ? (
                mid(corners[0], corners[3]), mid(corners[1], corners[2]),
                [(corners[0], corners[1]), (corners[3], corners[2])],
                [(corners[0], corners[3]), (corners[1], corners[2])]
            )
            : (
                mid(corners[0], corners[1]), mid(corners[3], corners[2]),
                [(corners[0], corners[3]), (corners[1], corners[2])],
                [(corners[0], corners[1]), (corners[3], corners[2])]
            )

        if !walled {
            // A deck to stand the posts on, then the posts themselves.
            painter.face(
                corners.map { ($0, base + 0.12) },
                fill: trim,
                shade: painter.light.shade(normal: SceneLight.up),
                outline: wallOutline,
                lineWidth: 0.7
            )
            for index in 0..<4 {
                let a = corners[index]
                let b = corners[(index + 1) % 4]
                let normal = SceneLight.wallNormal(from: a, to: b, about: object.transform.center)
                guard painter.facesCamera(normal) else { continue }
                painter.face([(a, base + 0.12), (b, base + 0.12), (b, base), (a, base)], fill: trim, shade: 0.28, outline: nil)
            }
            let centre = object.transform.center
            for corner in corners {
                let insetX: Double = corner.x + (centre.x - corner.x) * 0.12
                let insetY: Double = corner.y + (centre.y - corner.y) * 0.12
                fencePost(painter, at: Point(x: insetX, y: insetY), height: eavesZ - base, color: wall)
            }
        }

        // Walls, far ones first so near ones paint over them. Each takes its
        // tone from where the sun is rather than from its draw order, so two
        // buildings at right angles agree about which side is lit.
        let walls = [
            (corners[0], corners[1]), (corners[1], corners[2]),
            (corners[2], corners[3]), (corners[3], corners[0]),
        ].sorted { depth($0, painter) < depth($1, painter) }

        for wallEdge in walls where walled {
            let normal = SceneLight.wallNormal(from: wallEdge.0, to: wallEdge.1, about: object.transform.center)
            painter.face(
                [(wallEdge.0, base), (wallEdge.1, base), (wallEdge.1, eavesZ), (wallEdge.0, eavesZ)],
                fill: wall,
                shade: painter.light.shade(normal: normal) * (glazed ? 0.5 : 1),
                outline: wallOutline,
                material: glazed ? .glass : surfaces.wall,
                seed: object.id
            )
        }

        // The apex sits one roof thickness below the ridge line — which is
        // where a ceiling actually is, under the roof deck, and which stops a
        // sliver of wall showing above the roof at the gable whenever the two
        // meet at exactly the same height.
        let deckThickness = 0.18
        for (index, end) in gableEnds.enumerated() where walled {
            let apex = index == 0 ? ridgeA : ridgeB
            let normal = SceneLight.wallNormal(from: end.0, to: end.1, about: object.transform.center)
            painter.face(
                [(end.0, eavesZ), (end.1, eavesZ), (apex, ridgeZ - deckThickness), (apex, ridgeZ - deckThickness)],
                fill: wall,
                shade: painter.light.shade(normal: normal) * (glazed ? 0.5 : 1),
                outline: wallOutline,
                material: glazed ? .glass : surfaces.wall,
                seed: object.id + "gable"
            )
        }

        // Roof planes, oversailing the walls on all four sides.
        //
        // The overhang has to go out over the gable ends too, not just the
        // eaves. Pushing only the eaves out left each plane's raked edge
        // running from a corner that had moved to a ridge end that hadn't, so
        // the roof's rake and the gable wall below it sloped at different
        // angles and every roof in the scene looked twisted. Extending the
        // ridge by the same verge keeps each plane a parallelogram sitting
        // squarely over the building, with the gable wall inside it.
        let run = min(object.transform.width, object.transform.height) / 2
        let rise = max(0.1, ridge - eaves)
        let overhang = min(0.45, run * 0.22)
        let verge = overhang

        let ridgeSpan = (ridgeB.x - ridgeA.x, ridgeB.y - ridgeA.y)
        let ridgeLength = (ridgeSpan.0 * ridgeSpan.0 + ridgeSpan.1 * ridgeSpan.1).squareRoot()
        let along = ridgeLength > 0
            ? Point(x: ridgeSpan.0 / ridgeLength * verge, y: ridgeSpan.1 / ridgeLength * verge)
            : Point(x: 0, y: 0)
        let ridgeStart = Point(x: ridgeA.x - along.x, y: ridgeA.y - along.y)
        let ridgeEnd = Point(x: ridgeB.x + along.x, y: ridgeB.y + along.y)

        // `longEdges` is ordered so that edge.0 sits at the ridgeA end and
        // edge.1 at the ridgeB end, in both the along-x and along-y cases —
        // which is what lets the verge be applied to matching ends.
        let orderedSlopes = longEdges.sorted(by: { depth($0, painter) < depth($1, painter) })
        for (slopeIndex, edge) in orderedSlopes.enumerated() {
            let normal = SceneLight.roofNormal(from: edge.0, to: edge.1, run: run, rise: rise, about: object.transform.center)
            let flat = (normal.x * normal.x + normal.y * normal.y).squareRoot()
            let outward = flat > 0
                ? Point(x: normal.x / flat * overhang, y: normal.y / flat * overhang)
                : Point(x: 0, y: 0)
            let a = Point(x: edge.0.x + outward.x - along.x, y: edge.0.y + outward.y - along.y)
            let b = Point(x: edge.1.x + outward.x + along.x, y: edge.1.y + outward.y + along.y)
            // Plus, not minus. The roof plane extended back to the wall line
            // has to sit *above* the top of the wall; dropping it 5 cm below
            // put the wall through the roof at the gable, which is the pale
            // wedge that has been showing at every gable end.
            let eavesDrop = eavesZ - overhang * (rise / max(run, 0.1)) + 0.04

            painter.face(
                [(a, eavesDrop), (b, eavesDrop), (ridgeEnd, ridgeZ), (ridgeStart, ridgeZ)],
                fill: roof,
                shade: painter.light.shade(normal: normal),
                outline: Color.black.opacity(0.22),
                lineWidth: 0.7,
                material: glazed ? .glass : surfaces.roof,
                seed: object.id + "roof"
            )
            // Fascia along the eaves and a bargeboard up each rake: the cut
            // edges of the roof, seen end-on. Thin, but they are what give the
            // overhang thickness instead of leaving it a paper flap.
            let thickness = 0.18
            painter.face(
                [(a, eavesDrop), (b, eavesDrop), (b, eavesDrop - thickness), (a, eavesDrop - thickness)],
                fill: roof,
                shade: 0.34,
                outline: nil
            )
            // Only on the near slope: the far slope's rake boards face away
            // from the camera, and drawing them laid a flap across the gable.
            if slopeIndex == orderedSlopes.count - 1 {
                painter.face(
                    [(a, eavesDrop), (ridgeStart, ridgeZ), (ridgeStart, ridgeZ - thickness), (a, eavesDrop - thickness)],
                    fill: roof,
                    shade: 0.26,
                    outline: nil
                )
                painter.face(
                    [(b, eavesDrop), (ridgeEnd, ridgeZ), (ridgeEnd, ridgeZ - thickness), (b, eavesDrop - thickness)],
                    fill: roof,
                    shade: 0.26,
                    outline: nil
                )
            }
        }

        // Ridge cap, which is what makes the two planes read as a pitch.
        painter.line((ridgeStart, ridgeZ), (ridgeEnd, ridgeZ), color: .black.opacity(0.28), width: 1.6)

        if !walled {
            // An open pavilion has no glazing and no door.
        } else if glazed {
            glazingBars(painter, longEdges: longEdges, ridgeA: ridgeA, ridgeB: ridgeB, eavesZ: eavesZ, ridgeZ: ridgeZ, color: wallOutline)
            // The frame last, over everything: corner posts, a cill rail and
            // a ridge beam. Glass is mostly invisible, so a glasshouse is
            // read almost entirely from its frame.
            for corner in corners {
                painter.line((corner, base), (corner, eavesZ), color: trim, width: 1.8)
            }
            for index in 0..<4 {
                let a = corners[index], b = corners[(index + 1) % 4]
                painter.line((a, eavesZ), (b, eavesZ), color: trim, width: 1.6)
                painter.line((a, base + 0.05), (b, base + 0.05), color: trim, width: 1.6)
            }
            painter.line((ridgeA, ridgeZ), (ridgeB, ridgeZ), color: trim, width: 1.8)
        } else {
            openings(
                painter, object: object, corners: corners, base: base, eavesZ: eavesZ,
                outline: wallOutline, trim: trim, facing: facing, doorway: doorway
            )
        }
    }

    /// The barn: walls, then a steep lower roof slope breaking at a knuckle
    /// into a shallow upper one, with a five-sided gable end. Built on the
    /// same ridge/eaves scaffolding as `gabledBuilding` so the two agree
    /// about which way the building faces.
    static func gambrelBuilding(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        eaves: Double,
        knuckle: Double,
        ridge: Double,
        wall: Color,
        wallOutline: Color,
        roof: Color,
        trim: Color,
        facing: Point? = nil,
        surfaces: Massing.Surfaces
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }

        let eavesZ = base + eaves
        let knuckleZ = base + knuckle
        let ridgeZ = base + ridge
        let alongX = object.transform.width >= object.transform.height

        let (ridgeA, ridgeB, longEdges, gableEnds): (Point, Point, [(Point, Point)], [(Point, Point)]) = alongX
            ? (
                mid(corners[0], corners[3]), mid(corners[1], corners[2]),
                [(corners[0], corners[1]), (corners[3], corners[2])],
                [(corners[0], corners[3]), (corners[1], corners[2])]
            )
            : (
                mid(corners[0], corners[1]), mid(corners[3], corners[2]),
                [(corners[0], corners[3]), (corners[1], corners[2])],
                [(corners[0], corners[1]), (corners[3], corners[2])]
            )

        let walls = [
            (corners[0], corners[1]), (corners[1], corners[2]),
            (corners[2], corners[3]), (corners[3], corners[0]),
        ].sorted { depth($0, painter) < depth($1, painter) }
        for wallEdge in walls {
            painter.face(
                [(wallEdge.0, base), (wallEdge.1, base), (wallEdge.1, eavesZ), (wallEdge.0, eavesZ)],
                fill: wall,
                shade: painter.light.shade(normal: SceneLight.wallNormal(from: wallEdge.0, to: wallEdge.1, about: object.transform.center)),
                outline: wallOutline,
                material: surfaces.wall,
                seed: object.id
            )
        }

        // The knuckle sits partway in from the eaves — that break is the
        // whole silhouette.
        let run = min(object.transform.width, object.transform.height) / 2
        let knuckleInset = run * 0.45
        let overhang = min(0.45, run * 0.22)

        let ridgeSpan = (ridgeB.x - ridgeA.x, ridgeB.y - ridgeA.y)
        let ridgeLength = (ridgeSpan.0 * ridgeSpan.0 + ridgeSpan.1 * ridgeSpan.1).squareRoot()
        let along = ridgeLength > 0
            ? Point(x: ridgeSpan.0 / ridgeLength * overhang, y: ridgeSpan.1 / ridgeLength * overhang)
            : Point(x: 0, y: 0)
        let ridgeStart = Point(x: ridgeA.x - along.x, y: ridgeA.y - along.y)
        let ridgeEnd = Point(x: ridgeB.x + along.x, y: ridgeB.y + along.y)

        /// `point` moved straight in from (or, negative, out from) its own
        /// long edge — the direction the roof climbs.
        func inward(_ point: Point, from edge: (Point, Point), by amount: Double) -> Point {
            let normal = SceneLight.wallNormal(from: edge.0, to: edge.1, about: object.transform.center)
            let length = (normal.x * normal.x + normal.y * normal.y).squareRoot()
            guard length > 0 else { return point }
            return Point(x: point.x - normal.x / length * amount, y: point.y - normal.y / length * amount)
        }

        // Gable ends BEFORE the roof, so the roof covers them. Drawing them
        // after is what put a red wall across the white roof of the barn.
        // The five-sided profile goes down as a trapezoid under a triangle,
        // so each piece is a quad the texture can follow without a clip; and
        // moving a gable corner "in from its long edge" is the same as moving
        // it along the gable end, so the insets come from lerping.
        for (index, end) in gableEnds.enumerated() {
            let apex = index == 0 ? ridgeA : ridgeB
            let span = distance(end.0, end.1)
            guard span > 0 else { continue }
            let fraction = min(0.45, knuckleInset / span)
            let kneeA = lerp(end.0, end.1, fraction)
            let kneeB = lerp(end.1, end.0, fraction)
            let shade = painter.light.shade(normal: SceneLight.wallNormal(from: end.0, to: end.1, about: object.transform.center))

            painter.face(
                [(end.0, eavesZ), (end.1, eavesZ), (kneeB, knuckleZ), (kneeA, knuckleZ)],
                fill: wall,
                shade: shade,
                outline: wallOutline,
                material: surfaces.wall,
                seed: object.id + "gableLower"
            )
            painter.face(
                [(kneeA, knuckleZ), (kneeB, knuckleZ), (apex, ridgeZ - 0.18), (apex, ridgeZ - 0.18)],
                fill: wall,
                shade: shade,
                outline: wallOutline,
                material: surfaces.wall,
                seed: object.id + "gableUpper"
            )
        }

        for edge in longEdges.sorted(by: { depth($0, painter) < depth($1, painter) }) {
            // Both slopes oversail the gable by the same verge as the gabled
            // roof does, so the barn is detailed like everything else.
            let eavesA = Point(x: inward(edge.0, from: edge, by: -overhang).x - along.x,
                               y: inward(edge.0, from: edge, by: -overhang).y - along.y)
            let eavesB = Point(x: inward(edge.1, from: edge, by: -overhang).x + along.x,
                               y: inward(edge.1, from: edge, by: -overhang).y + along.y)
            let kneeA = Point(x: inward(edge.0, from: edge, by: knuckleInset).x - along.x,
                              y: inward(edge.0, from: edge, by: knuckleInset).y - along.y)
            let kneeB = Point(x: inward(edge.1, from: edge, by: knuckleInset).x + along.x,
                              y: inward(edge.1, from: edge, by: knuckleInset).y + along.y)

            let lowerRise = knuckle - eaves
            let eavesDrop = eavesZ - overhang * (lowerRise / max(knuckleInset, 0.1)) + 0.04
            let lowerNormal = SceneLight.roofNormal(from: edge.0, to: edge.1, run: knuckleInset, rise: lowerRise, about: object.transform.center)
            painter.face(
                [(eavesA, eavesDrop), (eavesB, eavesDrop), (kneeB, knuckleZ), (kneeA, knuckleZ)],
                fill: roof,
                shade: painter.light.shade(normal: lowerNormal),
                outline: Color.black.opacity(0.2),
                lineWidth: 0.7,
                material: surfaces.roof,
                seed: object.id + "lower"
            )
            painter.face(
                [(eavesA, eavesDrop), (eavesB, eavesDrop), (eavesB, eavesDrop - 0.18), (eavesA, eavesDrop - 0.18)],
                fill: roof,
                shade: 0.34,
                outline: nil
            )

            let upperNormal = SceneLight.roofNormal(from: kneeA, to: kneeB, run: max(0.1, run - knuckleInset), rise: ridge - knuckle, about: object.transform.center)
            painter.face(
                [(kneeA, knuckleZ), (kneeB, knuckleZ), (ridgeEnd, ridgeZ), (ridgeStart, ridgeZ)],
                fill: roof,
                shade: painter.light.shade(normal: upperNormal),
                outline: Color.black.opacity(0.2),
                lineWidth: 0.7,
                material: surfaces.roof,
                seed: object.id + "upper"
            )
        }

        painter.line((ridgeStart, ridgeZ), (ridgeEnd, ridgeZ), color: .black.opacity(0.28), width: 1.6)
        barnDoors(painter, object: object, corners: corners, base: base, eavesZ: eavesZ, trim: trim, facing: facing)
    }

    /// The big sliding door with its diagonal brace. Every barn in every
    /// reference has one, and it is what stops a red box being a red box.
    private static func barnDoors(
        _ painter: AxoPainter,
        object: PlanObject,
        corners: [Point],
        base: Double,
        eavesZ: Double,
        trim: Color,
        facing target: Point?
    ) {
        let front = frontWall(corners, of: object, facing: target)
        let width = distance(front.0, front.1)
        guard width * painter.scale > 40, eavesZ - base > 1.8 else { return }

        let doorHeight = min(3.2, (eavesZ - base) * 0.82)
        let half = min(0.28, 2.2 / width)
        let a = lerp(front.0, front.1, 0.5 - half)
        let b = lerp(front.0, front.1, 0.5 + half)
        painter.face(
            [(a, base), (b, base), (b, base + doorHeight), (a, base + doorHeight)],
            fill: trim,
            shade: 0.06,
            outline: Color.black.opacity(0.3),
            lineWidth: 0.7
        )
        // The X brace.
        painter.line((a, base), (b, base + doorHeight), color: .black.opacity(0.28), width: 1.2)
        painter.line((b, base), (a, base + doorHeight), color: .black.opacity(0.28), width: 1.2)
        let centre = lerp(a, b, 0.5)
        painter.line((centre, base), (centre, base + doorHeight), color: .black.opacity(0.3), width: 1.2)
    }

    /// Far-to-near ordering within one routine. The scene sorts everything
    /// against the camera afterwards, so this only decides ties — but a
    /// tie-break that assumes a fixed camera is still a tie-break that turns
    /// wrong when the view does, so it asks the painter.
    private static func depth(_ edge: (Point, Point), _ painter: AxoPainter, z: Double = 0) -> Double {
        (painter.depthOf(edge.0, z) + painter.depthOf(edge.1, z)) / 2
    }

    /// The wall the door goes on. Falls back to the south wall, the engine's
    /// own "front", when nothing serves the building. The geometry itself
    /// lives on `Transform`, where it is covered by tests that run on Linux —
    /// this layer can only be built on a Mac.
    private static func frontWall(_ corners: [Point], of object: PlanObject, facing target: Point?) -> (Point, Point) {
        guard corners.count == 4 else { return (corners.first ?? Point(x: 0, y: 0), corners.last ?? Point(x: 0, y: 0)) }
        let centre = object.transform.center
        return object.transform.wall(facing: target ?? Point(x: centre.x, y: centre.y + 1000))
    }

    /// How a building is entered.
    enum Doorway {
        /// A person door with a window either side.
        case pedestrian
        /// A wide opening with panel lines and no windows beside it — what a
        /// car actually drives through.
        case vehicle
    }

    /// A door on the wall that faces the way in, with windows either side.
    ///
    /// It used to go on the south wall always, whatever was out there. The
    /// engine routes a driveway from the gate to the garage in every plan
    /// (measured: eight of eight), so the garage ended up with a pedestrian
    /// door on a blank elevation facing a fence while the drive arrived at
    /// the back of it. The door now picks the wall whose outward normal
    /// points most nearly at whatever serves the building.
    private static func openings(
        _ painter: AxoPainter,
        object: PlanObject,
        corners: [Point],
        base: Double,
        eavesZ: Double,
        outline: Color,
        trim: Color,
        facing target: Point?,
        doorway: Doorway
    ) {
        guard corners.count == 4 else { return }
        let wallHeight = eavesZ - base
        guard wallHeight > 1.6 else { return }

        // The wall that looks at the target; the south wall when nothing
        // serves this building, which is the engine's own "front".
        let front = frontWall(corners, of: object, facing: target)
        let wallWidth = distance(front.0, front.1)
        guard wallWidth * painter.scale > 34 else { return }

        /// A framed panel on the chosen wall: trim behind, opening in front.
        func panel(from: Double, to: Double, bottom: Double, top: Double, fill: Color, frame: Double) {
            let inset = frame / max(wallWidth, 0.1)
            let outerA = lerp(front.0, front.1, max(0, from - inset))
            let outerB = lerp(front.0, front.1, min(1, to + inset))
            painter.face(
                [(outerA, bottom - frame), (outerB, bottom - frame), (outerB, top + frame), (outerA, top + frame)],
                fill: trim,
                shade: -0.04,
                outline: outline.opacity(0.55),
                lineWidth: 0.5
            )
            let innerA = lerp(front.0, front.1, from)
            let innerB = lerp(front.0, front.1, to)
            painter.face(
                [(innerA, bottom), (innerB, bottom), (innerB, top), (innerA, top)],
                fill: fill,
                shade: 0,
                outline: nil
            )
        }

        switch doorway {
        case .vehicle:
            // Wide enough to drive through, and tall enough to clear a roof
            // box: a garage door is most of the elevation it is on.
            let half = min(0.34, 2.6 / wallWidth)
            let height = min(2.6, wallHeight * 0.88)
            panel(
                from: 0.5 - half, to: 0.5 + half,
                bottom: base, top: base + height,
                fill: Color(hex: 0xb9bec4), frame: 0.14
            )
            // Panel lines, which is what makes it an up-and-over door rather
            // than a hole in the wall.
            guard wallWidth * painter.scale > 60 else { return }
            for step in 1...3 {
                let z = base + height * Double(step) / 4
                painter.line(
                    (lerp(front.0, front.1, 0.5 - half), z),
                    (lerp(front.0, front.1, 0.5 + half), z),
                    color: outline.opacity(0.45),
                    width: 0.8
                )
            }

        case .pedestrian:
            let doorHeight = min(2.1, wallHeight * 0.8)
            let doorHalf = min(0.45, wallWidth * 0.06) / wallWidth
            panel(
                from: 0.5 - doorHalf, to: 0.5 + doorHalf,
                bottom: base, top: base + doorHeight,
                fill: Color(hex: 0x5a3f2c), frame: 0.12
            )
            let stepA = lerp(front.0, front.1, 0.5 - doorHalf * 1.4)
            let stepB = lerp(front.0, front.1, 0.5 + doorHalf * 1.4)
            painter.line((stepA, base + 0.06), (stepB, base + 0.06), color: trim, width: max(1.4, CGFloat(0.22 * painter.scale)))

            guard wallWidth * painter.scale > 60 else { return }
            let sillZ = base + wallHeight * 0.4
            let headZ = base + wallHeight * 0.76
            for fraction in [0.22, 0.78] {
                panel(
                    from: fraction - 0.08, to: fraction + 0.08,
                    bottom: sillZ, top: headZ,
                    fill: Color(hex: 0x86b4cf), frame: 0.1
                )
                let middle = lerp(front.0, front.1, fraction)
                painter.line((middle, sillZ), (middle, headZ), color: trim.opacity(0.85), width: 0.9)
                let midZ = (sillZ + headZ) / 2
                painter.line(
                    (lerp(front.0, front.1, fraction - 0.08), midZ),
                    (lerp(front.0, front.1, fraction + 0.08), midZ),
                    color: trim.opacity(0.85),
                    width: 0.9
                )
            }
        }
    }

    /// Two beds of seedlings running the length of the house, with a walkway
    /// between them — the arrangement every reference greenhouse has, and
    /// what stops a glass box reading as a bus shelter.
    private static func greenhouseInterior(_ painter: AxoPainter, object: PlanObject, base: Double, alongX: Bool) {
        let corners = object.transform.corners
        guard corners.count == 4, painter.scale > 2 else { return }
        let soil = Color(hex: 0x6f4a30)
        let leaf = Color(hex: 0x5fa341)
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: object.transform.center, z: base + 0.5) }

        for fraction in [0.26, 0.74] {
            let (a, b): (Point, Point) = alongX
                ? (lerp(corners[0], corners[3], fraction), lerp(corners[1], corners[2], fraction))
                : (lerp(corners[0], corners[1], fraction), lerp(corners[3], corners[2], fraction))
            let bed: [(Point, Double)] = [
                (lerp(a, b, 0.08), base + 0.3),
                (lerp(b, a, 0.08), base + 0.3),
                (lerp(b, a, 0.08), base),
                (lerp(a, b, 0.08), base),
            ]
            painter.face(bed, fill: soil, shade: 0.1, outline: nil)

            let count = max(3, min(14, Int(distance(a, b) / 0.8)))
            for index in 0...count {
                let t = Double(index) / Double(count)
                let at = lerp(lerp(a, b, 0.08), lerp(b, a, 0.08), t)
                let top = painter.project(at, base + 0.72)
                let root = painter.project(at, base + 0.3)
                ops.stroke(
                    Path { path in
                        path.move(to: root)
                        path.addLine(to: top)
                    },
                    with: (leaf),
                    lineWidth: max(1, CGFloat(0.16 * painter.scale))
                )
            }
        }
    }

    private static func glazingBars(
        _ painter: AxoPainter,
        longEdges: [(Point, Point)],
        ridgeA: Point,
        ridgeB: Point,
        eavesZ: Double,
        ridgeZ: Double,
        color: Color
    ) {
        for edge in longEdges {
            for fraction in stride(from: 0.12, through: 0.88, by: 0.19) {
                let eavesPoint = lerp(edge.0, edge.1, fraction)
                let ridgePoint = lerp(ridgeA, ridgeB, fraction)
                painter.line((eavesPoint, eavesZ), (ridgePoint, ridgeZ), color: color.opacity(0.45), width: 0.6)
            }
        }
    }

    static func chimney(_ painter: AxoPainter, object: PlanObject, base: Double, ridgeZ: Double, wall: Color, outline: Color) {
        let centre = object.transform.center
        let offset = min(object.transform.width, object.transform.height) * 0.22
        let stack = Point(x: centre.x + offset, y: centre.y - offset)
        let half = 0.32
        let quad = [
            Point(x: stack.x - half, y: stack.y - half),
            Point(x: stack.x + half, y: stack.y - half),
            Point(x: stack.x + half, y: stack.y + half),
            Point(x: stack.x - half, y: stack.y + half),
        ]
        let top = ridgeZ + 0.9
        for i in 0..<4 {
            let a = quad[i], b = quad[(i + 1) % 4]
            painter.face([(a, ridgeZ - 0.3), (b, ridgeZ - 0.3), (b, top), (a, top)], fill: wall, shade: i < 2 ? 0.3 : 0.1, outline: outline, lineWidth: 0.5)
        }
        painter.face(quad.map { ($0, top) }, fill: wall, shade: -0.12, outline: outline, lineWidth: 0.5)
    }

    /// A cultivated bed: tilled soil, furrows running along it, and plants
    /// set out on a grid. The references are unanimous that this is what makes
    /// a plot read as a farm — a green rectangle with lines on it reads as a
    /// lawn with a texture bug. Every dimension is a real measurement from
    /// `Massing.planting`, and the foliage is clamped to the spacing it grows
    /// in, so a plant can never come out taller than the shed next to it.
    static func plantedRows(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        crop: Color,
        outline: Color
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let planting = Massing.planting(for: object)
        let width = object.transform.width
        let depthM = object.transform.height
        let alongX = width >= depthM
        let bedZ = base + planting.bed
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: object.transform.center, z: bedZ) }

        // The bed stands slightly proud of the grass, with its own cut sides.
        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: object.transform.center)
            guard painter.facesCamera(normal) else { continue }
            painter.face(
                [(a, bedZ), (b, bedZ), (b, base), (a, base)],
                fill: tilledSoil,
                shade: painter.light.shade(normal: normal),
                outline: nil
            )
        }
        painter.face(
            corners.map { ($0, bedZ) },
            fill: tilledSoil,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: outline.opacity(0.45),
            lineWidth: 0.7
        )

        let across = alongX ? depthM : width
        let along = alongX ? width : depthM
        let rowCount = max(1, min(40, Int(across / planting.rowSpacing)))
        let rowSpacing = across / Double(rowCount)
        guard rowSpacing * painter.scale > 3 else { return }

        func furrow(_ index: Int) -> (Point, Point) {
            let fraction = (Double(index) + 0.5) / Double(rowCount)
            return alongX
                ? (lerp(corners[0], corners[3], fraction), lerp(corners[1], corners[2], fraction))
                : (lerp(corners[0], corners[1], fraction), lerp(corners[3], corners[2], fraction))
        }

        // Furrows: a dark line with a light one just below it, which is what
        // gives tilled ground its corduroy look in the references.
        for index in 0..<rowCount {
            let (a, b) = furrow(index)
            let rowA = lerp(a, b, 0.03)
            let rowB = lerp(b, a, 0.03)
            painter.line((rowA, bedZ), (rowB, bedZ), color: .black.opacity(0.22), width: 1.4)
            painter.line((rowA, bedZ + 0.02), (rowB, bedZ + 0.02), color: .white.opacity(0.10), width: 0.8)
        }

        // Below a few points across, plants turn the bed to grey mush; the
        // furrows carry it instead, which is exactly what a field does at a
        // distance in the references.
        let plantCount = max(1, min(40, Int(along / planting.plantSpacing)))
        let plantSpacing = along / Double(plantCount)
        let spread = min(planting.spread, min(rowSpacing, plantSpacing) * 0.9)
        guard spread * painter.scale > 5 else { return }

        let leaf = crop
        let leafLight = crop.mix(with: .white, by: 0.24)
        let leafDark = crop.mix(with: .black, by: 0.22)
        let radius = CGFloat(spread / 2 * painter.scale)

        for row in 0..<rowCount {
            let (a, b) = furrow(row)
            for index in 0..<plantCount {
                let t = (Double(index) + 0.5) / Double(plantCount)
                let at = lerp(lerp(a, b, 0.03), lerp(b, a, 0.03), t)
                let key = row * 97 + index
                let vary = 0.82 + AxoNoise.value(object.id, key, 1) * 0.36
                let height = planting.height * vary

                if planting.stemmed {
                    // Grain and vines: a visible stem with the foliage at the
                    // top, because that is what they look like.
                    let root = painter.project(at, bedZ)
                    let top = painter.project(at, bedZ + height)
                    ops.stroke(
                        Path { path in
                            path.move(to: root)
                            path.addLine(to: top)
                        },
                        with: (leafDark),
                        lineWidth: max(1, radius * 0.3)
                    )
                    ops.fill(
                        Path(ellipseIn: CGRect(x: top.x - radius * 0.7, y: top.y - radius * 0.8, width: radius * 1.4, height: radius * 1.5)),
                        with: (leaf)
                    )
                    continue
                }

                // Everything else is a low mound: a few overlapping lobes,
                // wider than tall, sitting on the soil.
                let centre = painter.project(at, bedZ + height * 0.45)
                for lobe in -1...1 {
                    let offset = CGFloat(lobe) * radius * 0.5
                    let size = radius * (lobe == 0 ? 1.0 : 0.78)
                    let rect = CGRect(
                        x: centre.x + offset - size,
                        y: centre.y - size * 0.72 - (lobe == 0 ? radius * 0.18 : 0),
                        width: size * 2,
                        height: size * 1.44
                    )
                    ops.fill(
                        Path(ellipseIn: rect),
                        with: (lobe == -1 ? leafLight : (lobe == 1 ? leafDark : leaf))
                    )
                }
            }
        }
    }

    /// Tilled earth. One colour for every bed, because the thing that varies
    /// between a potato patch and a herb bed is what grows on it.
    private static let tilledSoil = Color(hex: 0x6f4a30)

    /// A canopy built from overlapping rounded lobes in layered greens, which
    /// is how every isometric reference draws a tree — a single flat ellipse
    /// reads as a lollipop and is the main reason the old orchards looked
    /// like green coins on sticks. The lobes are placed from a hash of the
    /// tree's own position, so each tree is its own shape and none of them
    /// change when the view redraws.
    static func tree(
        _ painter: AxoPainter,
        at position: Point,
        height: Double,
        radius: Double,
        conifer: Bool,
        foliage: Color,
        outline: Color,
        seed: String = ""
    ) {
        let key = seed.isEmpty ? "\(Int(position.x * 7))-\(Int(position.y * 7))" : seed
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: position, z: height * 0.6) }
        let trunkTop = height * (conifer ? 0.26 : 0.5)
        let trunkWidth = max(1.4, CGFloat(radius * 0.22 * painter.scale))
        painter.line((position, 0), (position, trunkTop), color: Color(hex: 0x7b5433), width: trunkWidth)
        painter.line((position, 0), (position, trunkTop * 0.55), color: Color(hex: 0x5f3f26), width: trunkWidth * 0.45)

        // Three tones around the foliage colour rather than up from it — the
        // base hue stays the tree's colour, instead of every lobe drifting
        // pale.
        let dark = mixed(foliage, with: .black, 0.20)
        let mid = foliage
        let light = mixed(foliage, with: .white, 0.20)

        if conifer {
            // Three rounded skirts, widest at the bottom, each a little
            // lighter than the one below it.
            for tier in 0..<3 {
                let t = Double(tier)
                let bottom = trunkTop + (height - trunkTop) * (t / 3.4)
                let top = trunkTop + (height - trunkTop) * ((t + 1.7) / 3)
                let r = radius * (1 - t * 0.24)
                let rx = CGFloat(painter.ellipseAxes(r).rx)
                let ry = CGFloat(painter.ellipseAxes(r).ry)
                let baseScreen = painter.project(position, bottom)
                let apex = painter.project(position, top)

                var cone = Path()
                cone.move(to: CGPoint(x: baseScreen.x - rx, y: baseScreen.y))
                cone.addQuadCurve(to: apex, control: CGPoint(x: baseScreen.x - rx * 0.62, y: baseScreen.y - ry * 1.1))
                cone.addQuadCurve(
                    to: CGPoint(x: baseScreen.x + rx, y: baseScreen.y),
                    control: CGPoint(x: baseScreen.x + rx * 0.62, y: baseScreen.y - ry * 1.1)
                )
                cone.addCurve(
                    to: CGPoint(x: baseScreen.x - rx, y: baseScreen.y),
                    control1: CGPoint(x: baseScreen.x + rx * 0.55, y: baseScreen.y + ry * 1.15),
                    control2: CGPoint(x: baseScreen.x - rx * 0.55, y: baseScreen.y + ry * 1.15)
                )
                cone.closeSubpath()
                ops.fill(cone, with: (tier == 0 ? dark : (tier == 1 ? mid : light)))
                ops.stroke(cone, with: (outline.opacity(0.45)), lineWidth: 0.6)
            }
            return
        }

        // Deciduous: a cluster of lobes around the crown centre, drawn back
        // to front so the lit ones on the sun side end up on top.
        let crownZ = height - radius * 0.45
        let lobeCount = painter.scale > 2.5 ? 7 : 4
        var lobes: [(offset: CGPoint, radius: CGFloat, tone: Color)] = []
        let unit = CGFloat(painter.ellipseAxes(radius).rx)
        guard unit > 2 else {
            let centre = painter.project(position, crownZ)
            let rect = CGRect(x: centre.x - unit, y: centre.y - unit * 0.92, width: unit * 2, height: unit * 1.84)
            ops.fill(Path(ellipseIn: rect), with: (mid))
            return
        }

        for index in 0..<lobeCount {
            let angle = Double(index) / Double(lobeCount) * 2 * .pi + AxoNoise.jitter(key, index, 1, 0.5)
            let spread = 0.34 + AxoNoise.value(key, index, 2) * 0.34
            let offset = CGPoint(
                x: unit * CGFloat(cos(angle) * spread),
                y: unit * CGFloat(sin(angle) * spread) * 0.82
            )
            let size = unit * CGFloat(0.52 + AxoNoise.value(key, index, 3) * 0.28)
            // Lit from the top-left, matching the scene's sun.
            let lit = offset.x < 0 && offset.y < 0
            lobes.append((offset, size, lit ? light : (offset.y > 0 ? dark : mid)))
        }
        lobes.append((CGPoint(x: 0, y: -unit * 0.1), unit * 0.78, mid))
        lobes.sort { $0.offset.y > $1.offset.y }

        let centre = painter.project(position, crownZ)
        for lobe in lobes {
            let rect = CGRect(
                x: centre.x + lobe.offset.x - lobe.radius,
                y: centre.y + lobe.offset.y - lobe.radius * 0.94,
                width: lobe.radius * 2,
                height: lobe.radius * 1.88
            )
            ops.fill(Path(ellipseIn: rect), with: (lobe.tone))
        }
    }

    /// Blend toward another colour. `Color` won't do arithmetic, and the
    /// palette arrives as `Color` from `CategoryStyle`, so the tones of a
    /// canopy are made by compositing rather than by mixing components.
    private static func mixed(_ base: Color, with other: Color, _ amount: Double) -> Color {
        base.mix(with: other, by: amount)
    }

    /// Rows of tilted panels on legs, facing south. A ground array painted
    /// flat on the grass with a plan glyph on it was the one thing left in
    /// the scene with no form at all; the references draw it as panels, and
    /// the tilt is the whole reason it is recognisable.
    static func solarPanels(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        height: Double,
        panel: Color,
        frame: Color
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let low = base + height * 0.3
        let high = base + height

        // Rows run east-west and step southward, so each faces the sun.
        let rowCount = max(1, min(6, Int(object.transform.height / 2.4)))
        for row in 0..<rowCount {
            let t0 = Double(row) / Double(rowCount)
            let t1 = (Double(row) + 0.72) / Double(rowCount)
            let northA = lerp(corners[0], corners[3], t0)
            let northB = lerp(corners[1], corners[2], t0)
            let southA = lerp(corners[0], corners[3], t1)
            let southB = lerp(corners[1], corners[2], t1)

            // Legs first, so the panel sits on top of them.
            painter.line((southA, base), (southA, low), color: frame, width: 1.6)
            painter.line((southB, base), (southB, low), color: frame, width: 1.6)
            painter.face(
                [(northA, high), (northB, high), (southB, low), (southA, low)],
                fill: panel,
                shade: painter.light.shade(normal: (x: 0, y: 0.42, z: 0.91)),
                outline: frame,
                lineWidth: 0.8
            )
            // Cell grid, which is what names the thing.
            let cells = max(2, min(10, Int(object.transform.width / 1.2)))
            for cell in 1..<cells {
                let f = Double(cell) / Double(cells)
                painter.line(
                    (lerp(northA, northB, f), high),
                    (lerp(southA, southB, f), low),
                    color: frame.opacity(0.7),
                    width: 0.6
                )
            }
        }
    }

    /// The way in. The engine has always known where it is — `findGatePoint`
    /// puts it on the road-facing boundary edge nearest the house, and the
    /// driveway and the entrance walk both run to it — but nothing drew it, so
    /// the plot came out ringed by an unbroken fence with paths running into
    /// it. Two taller jamb posts and a leaf swung open, which is what every
    /// reference does.
    static func gate(
        _ painter: AxoPainter,
        at centre: Point,
        along direction: Point,
        width: Double,
        height: Double,
        post: Color,
        leaf: Color
    ) {
        let half = width / 2
        let jambA = Point(x: centre.x - direction.x * half, y: centre.y - direction.y * half)
        let jambB = Point(x: centre.x + direction.x * half, y: centre.y + direction.y * half)
        let jambHeight = height * 1.35

        // The leaf swings inward off the far jamb, so the opening reads as an
        // opening rather than as a missing section of fence.
        let swing = Point(x: -direction.y, y: direction.x)
        let tip = Point(
            x: jambB.x - direction.x * width * 0.72 + swing.x * width * 0.62,
            y: jambB.y - direction.y * width * 0.72 + swing.y * width * 0.62
        )
        let light = leaf.mix(with: .white, by: 0.2)
        let dark = leaf.mix(with: .black, by: 0.28)

        for rail in [0.28, 0.58, 0.88] {
            painter.line((jambB, height * rail), (tip, height * rail), color: rail == 0.88 ? light : leaf, width: 1.6)
        }
        painter.line((jambB, height * 0.28), (tip, height * 0.88), color: dark, width: 1.2)
        painter.line((tip, 0), (tip, height * 0.95), color: leaf, width: 1.8)

        fencePost(painter, at: jambA, height: jambHeight, color: post)
        fencePost(painter, at: jambB, height: jambHeight, color: post)
    }

    /// What a technical enclosure is: a cabinet on a plinth under a flat roof
    /// with a drip edge, with a door and the vents or fins its contents need.
    ///
    /// A battery room and an inverter room were both a plain box with a symbol
    /// on the lid. They are genuinely similar things, so the difference has to
    /// be drawn rather than coloured: batteries need a lot of air, so that one
    /// gets a full louvred panel; an inverter sheds heat through fins and runs
    /// conduit out to the array.
    enum Cabinet {
        case louvred
        case finned
    }

    static func cabinet(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        height: Double,
        wall: Color,
        roof: Color,
        trim: Color,
        kind: Cabinet,
        facing target: Point?
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let plinthZ = base + 0.16
        let eavesZ = plinthZ + height

        func expanded(by amount: Double) -> [Point] {
            corners.map { corner in
                Point(
                    x: corner.x + (corner.x >= centre.x ? amount : -amount),
                    y: corner.y + (corner.y >= centre.y ? amount : -amount)
                )
            }
        }

        // Concrete plinth, a little proud of the walls.
        let plinth = expanded(by: 0.12)
        for index in 0..<4 {
            let a = plinth[index], b = plinth[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(a, plinthZ), (b, plinthZ), (b, base), (a, base)], fill: Color(hex: 0xb8b4ac), shade: 0.26, outline: nil)
        }
        painter.face(plinth.map { ($0, plinthZ) }, fill: Color(hex: 0xc6c2b9), shade: 0.05, outline: nil)

        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            painter.face(
                [(a, plinthZ), (b, plinthZ), (b, eavesZ), (a, eavesZ)],
                fill: wall,
                shade: painter.light.shade(normal: normal),
                outline: wall.mix(with: .black, by: 0.35),
                lineWidth: 0.7
            )
        }

        // Flat roof with an overhang and a drip edge, so it is a roof.
        let lid = expanded(by: 0.16)
        painter.face(
            lid.map { ($0, eavesZ + 0.1) },
            fill: roof,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: roof.mix(with: .black, by: 0.35),
            lineWidth: 0.7
        )
        for index in 0..<4 {
            let a = lid[index], b = lid[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(a, eavesZ + 0.1), (b, eavesZ + 0.1), (b, eavesZ - 0.02), (a, eavesZ - 0.02)], fill: roof, shade: 0.34, outline: nil)
        }

        guard painter.scale > 3 else { return }
        let front = frontWall(corners, of: object, facing: target)
        let span = distance(front.0, front.1)
        guard span > 0.8 else { return }

        // A door, narrow: these are rooms you step into, not drive into.
        let doorHalf = min(0.4, span * 0.22) / span
        let doorTop = plinthZ + min(2.0, height * 0.82)
        painter.face(
            [(lerp(front.0, front.1, 0.5 - doorHalf), plinthZ),
             (lerp(front.0, front.1, 0.5 + doorHalf), plinthZ),
             (lerp(front.0, front.1, 0.5 + doorHalf), doorTop),
             (lerp(front.0, front.1, 0.5 - doorHalf), doorTop)],
            fill: trim,
            shade: 0.08,
            outline: wall.mix(with: .black, by: 0.4),
            lineWidth: 0.6
        )
        painter.line(
            (lerp(front.0, front.1, 0.5 + doorHalf * 0.55), plinthZ + height * 0.45),
            (lerp(front.0, front.1, 0.5 + doorHalf * 0.8), plinthZ + height * 0.45),
            color: wall.mix(with: .black, by: 0.5),
            width: 1.6
        )

        switch kind {
        case .louvred:
            // Slats across the whole front above the door: battery rooms are
            // mostly ventilation.
            let slats = max(3, min(8, Int(height / 0.28)))
            for step in 1...slats {
                let z = plinthZ + height * (0.3 + 0.62 * Double(step) / Double(slats + 1))
                painter.line(
                    (lerp(front.0, front.1, 0.08), z),
                    (lerp(front.0, front.1, 0.92), z),
                    color: wall.mix(with: .black, by: 0.45),
                    width: 1.6
                )
            }
        case .finned:
            // Heat-sink fins down one side, and conduit heading off to the
            // array.
            let side = (corners[1], corners[2])
            let fins = max(3, min(9, Int(distance(side.0, side.1) / 0.3)))
            for step in 1...fins {
                let t = Double(step) / Double(fins + 1)
                painter.line(
                    (lerp(side.0, side.1, t), plinthZ + 0.2),
                    (lerp(side.0, side.1, t), eavesZ - 0.2),
                    color: wall.mix(with: .black, by: 0.4),
                    width: 1.4
                )
            }
            let conduitFoot = lerp(front.0, front.1, 0.9)
            painter.line((conduitFoot, plinthZ + 0.3), (conduitFoot, eavesZ + 0.35), color: trim.mix(with: .black, by: 0.2), width: max(1.8, CGFloat(0.1 * painter.scale)))
        }
    }

    /// A septic tank is buried. What you see is a low grassed mound with
    /// manhole covers on it and a vent stack — not a building, and not the
    /// flat slab with a plan symbol it used to be.
    static func septicField(_ painter: AxoPainter, object: PlanObject, base: Double, mound: Color, cover: Color) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let width = object.transform.width
        let depth = object.transform.height
        let topZ = base + 0.22
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: centre, z: topZ) }

        // Battered sides, so it reads as earth heaped over something rather
        // than a slab dropped on the grass.
        let crown = corners.map { corner in
            Point(
                x: corner.x + (corner.x >= centre.x ? -0.5 : 0.5),
                y: corner.y + (corner.y >= centre.y ? -0.5 : 0.5)
            )
        }
        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let ca = crown[index], cb = crown[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(ca, topZ), (cb, topZ), (b, base), (a, base)], fill: mound, shade: painter.light.shade(normal: normal), outline: nil)
        }
        painter.face(
            crown.map { ($0, topZ) },
            fill: mound,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: mound.mix(with: .black, by: 0.25),
            lineWidth: 0.7
        )

        guard painter.scale > 3 else { return }

        // Two inspection covers along the long axis.
        let alongX = width >= depth
        let radius = min(0.42, min(width, depth) * 0.16)
        let rx = CGFloat(painter.ellipseAxes(radius).rx)
        let ry = CGFloat(painter.ellipseAxes(radius).ry)
        for fraction in [0.32, 0.68] {
            let at = alongX
                ? Point(x: centre.x + (fraction - 0.5) * width * 0.7, y: centre.y)
                : Point(x: centre.x, y: centre.y + (fraction - 0.5) * depth * 0.7)
            let screen = painter.project(at, topZ + 0.02)
            let rect = CGRect(x: screen.x - rx, y: screen.y - ry, width: rx * 2, height: ry * 2)
            ops.fill(Path(ellipseIn: rect), with: (cover))
            ops.stroke(Path(ellipseIn: rect), with: (cover.mix(with: .black, by: 0.45)), lineWidth: 1.2)
            ops.stroke(
                Path(ellipseIn: rect.insetBy(dx: rx * 0.3, dy: ry * 0.3)),
                with: (cover.mix(with: .black, by: 0.3)),
                lineWidth: 0.8
            )
        }

        // Vent stack at one end, with a cowl.
        let vent = alongX
            ? Point(x: centre.x - width * 0.38, y: centre.y + depth * 0.28)
            : Point(x: centre.x + width * 0.28, y: centre.y - depth * 0.38)
        painter.line((vent, topZ), (vent, topZ + 1.25), color: Color(hex: 0x6f7a80), width: max(1.8, CGFloat(0.1 * painter.scale)))
        let cap = painter.project(vent, topZ + 1.3)
        ops.fill(
            Path(ellipseIn: CGRect(x: cap.x - rx * 0.5, y: cap.y - ry * 0.5, width: rx, height: ry)),
            with: (Color(hex: 0x8d979d))
        )
    }

    /// A paved terrace with something on it. A patio is where people sit, and
    /// a flat lilac diamond with a plan glyph on it says none of that — paving
    /// joints, a table under a parasol and stools around it do.
    static func patio(_ painter: AxoPainter, object: PlanObject, base: Double, paving: Color) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let slabZ = base + 0.12
        let joint = paving.mix(with: .black, by: 0.22)
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: centre, z: slabZ + 1.2) }

        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(a, slabZ), (b, slabZ), (b, base), (a, base)], fill: paving, shade: 0.28, outline: nil)
        }
        painter.face(
            corners.map { ($0, slabZ) },
            fill: paving,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: joint,
            lineWidth: 0.7,
            material: .brick,
            seed: object.id
        )

        guard painter.scale > 3.5 else { return }

        // A round table with a parasol, and stools around it. Small, so it
        // reads as furniture rather than as more buildings.
        let tableR = min(0.62, min(object.transform.width, object.transform.height) * 0.16)
        let tableZ = slabZ + 0.74
        let timber = Color(hex: 0x9a6b42)
        let rx = CGFloat(painter.ellipseAxes(tableR).rx)
        let ry = CGFloat(painter.ellipseAxes(tableR).ry)

        for step in 0..<4 {
            let angle = Double(step) / 4 * 2 * .pi + .pi / 4
            let seat = Point(x: centre.x + cos(angle) * tableR * 2.1, y: centre.y + sin(angle) * tableR * 2.1)
            painter.line((seat, slabZ), (seat, slabZ + 0.42), color: timber.mix(with: .black, by: 0.3), width: max(1.4, CGFloat(0.12 * painter.scale)))
            let top = painter.project(seat, slabZ + 0.42)
            let seatR = rx * 0.42
            ops.fill(
                Path(ellipseIn: CGRect(x: top.x - seatR, y: top.y - seatR * 0.6, width: seatR * 2, height: seatR * 1.2)),
                with: (timber)
            )
        }

        painter.line((centre, slabZ), (centre, tableZ), color: timber.mix(with: .black, by: 0.35), width: max(1.6, CGFloat(0.14 * painter.scale)))
        let tableTop = painter.project(centre, tableZ)
        ops.fill(
            Path(ellipseIn: CGRect(x: tableTop.x - rx, y: tableTop.y - ry, width: rx * 2, height: ry * 2)),
            with: (timber.mix(with: .white, by: 0.15))
        )
        ops.stroke(
            Path(ellipseIn: CGRect(x: tableTop.x - rx, y: tableTop.y - ry, width: rx * 2, height: ry * 2)),
            with: (timber.mix(with: .black, by: 0.3)),
            lineWidth: 0.8
        )

        // Parasol: a pole and a shallow cone over the table.
        let mastZ = tableZ + 1.5
        painter.line((centre, tableZ), (centre, mastZ), color: timber, width: max(1.2, CGFloat(0.08 * painter.scale)))
        let canopyR = tableR * 2.4
        let cx = CGFloat(painter.ellipseAxes(canopyR).rx)
        let cy = CGFloat(painter.ellipseAxes(canopyR).ry)
        let hub = painter.project(centre, mastZ)
        let brim = painter.project(centre, mastZ - 0.42)
        var canopy = Path()
        canopy.move(to: CGPoint(x: brim.x - cx, y: brim.y))
        canopy.addQuadCurve(to: hub, control: CGPoint(x: brim.x - cx * 0.5, y: hub.y - cy * 0.3))
        canopy.addQuadCurve(to: CGPoint(x: brim.x + cx, y: brim.y), control: CGPoint(x: brim.x + cx * 0.5, y: hub.y - cy * 0.3))
        canopy.addCurve(
            to: CGPoint(x: brim.x - cx, y: brim.y),
            control1: CGPoint(x: brim.x + cx * 0.55, y: brim.y + cy * 1.2),
            control2: CGPoint(x: brim.x - cx * 0.55, y: brim.y + cy * 1.2)
        )
        canopy.closeSubpath()
        ops.fill(canopy, with: (Color(hex: 0xd96f5a)))
        ops.fill(canopy, with: (.white.opacity(0.12)))
        ops.stroke(canopy, with: (Color(hex: 0xa04d3c)), lineWidth: 0.8)
    }

    /// A micro-hydro set: a housing on the bank with an overshot wheel turning
    /// beside it and a flume feeding the top of it. A plain box with a plan
    /// glyph painted on the lid could be anything.
    static func turbine(_ painter: AxoPainter, object: PlanObject, base: Double, housing: Color, metal: Color) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let width = object.transform.width
        let depth = object.transform.height
        let alongX = width >= depth
        let housingTop = base + 1.9
        var ops = AxoOps()
        defer { ops.emit(into: painter, at: centre, z: base + 1.0) }

        // Housing: the near half of the footprint.
        let shed = corners.enumerated().map { index, corner -> Point in
            let pullIn = index == 0 || index == 1
            let amount = (alongX ? width : depth) * 0.34
            return alongX
                ? Point(x: corner.x, y: corner.y + (pullIn ? amount : 0))
                : Point(x: corner.x + (pullIn ? amount : 0), y: corner.y)
        }
        for index in 0..<4 {
            let a = shed[index], b = shed[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face(
                [(a, base), (b, base), (b, housingTop), (a, housingTop)],
                fill: housing,
                shade: painter.light.shade(normal: normal),
                outline: housing.mix(with: .black, by: 0.35),
                lineWidth: 0.7,
                material: .board,
                seed: object.id
            )
        }
        painter.face(
            shed.map { ($0, housingTop) },
            fill: metal,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: metal.mix(with: .black, by: 0.3),
            lineWidth: 0.7,
            material: .metalRoof,
            seed: object.id + "lid"
        )

        guard painter.scale > 2.5 else { return }

        // The wheel, standing in a vertical plane beside the housing. Its
        // points are swept in that plane and projected one by one, which the
        // projection being linear makes exact.
        let radius = min(1.5, min(width, depth) * 0.42)
        let hubZ = base + radius + 0.15
        let hub = alongX
            ? Point(x: centre.x, y: centre.y - depth * 0.3)
            : Point(x: centre.x - width * 0.3, y: centre.y)

        func rimPoint(_ angle: Double) -> (Point, Double) {
            let along = cos(angle) * radius
            let offset = alongX ? Point(x: hub.x + along, y: hub.y) : Point(x: hub.x, y: hub.y + along)
            return (offset, hubZ + sin(angle) * radius)
        }

        var rim = Path()
        for step in 0...24 {
            let angle = Double(step) / 24 * 2 * .pi
            let (point, z) = rimPoint(angle)
            let screen = painter.project(point, z)
            if step == 0 { rim.move(to: screen) } else { rim.addLine(to: screen) }
        }
        rim.closeSubpath()
        ops.fill(rim, with: (metal.mix(with: .black, by: 0.12)))
        ops.stroke(rim, with: (metal.mix(with: .black, by: 0.45)), lineWidth: 1.4)

        // Paddles and spokes: what makes it a wheel rather than a disc.
        for step in 0..<8 {
            let angle = Double(step) / 8 * 2 * .pi
            let (outer, outerZ) = rimPoint(angle)
            painter.line((hub, hubZ), (outer, outerZ), color: metal.mix(with: .black, by: 0.4), width: 1)
            let (next, nextZ) = rimPoint(angle + .pi / 8)
            painter.line((outer, outerZ), (next, nextZ), color: Color(hex: 0x8a6a45), width: 2.2)
        }

        // Flume, feeding the top of the wheel from the bank.
        let (crest, crestZ) = rimPoint(.pi / 2)
        let inletOffset = alongX ? Point(x: crest.x, y: crest.y - radius * 1.6) : Point(x: crest.x - radius * 1.6, y: crest.y)
        painter.line((inletOffset, crestZ + 0.35), (crest, crestZ + 0.12), color: Color(hex: 0x8a6a45), width: max(2, CGFloat(0.3 * painter.scale)))
    }

    /// A swimming pool: a coping walk around a basin of water sunk below it,
    /// with a shallow end and a ladder. It was a flat lilac slab with a
    /// swimmer glyph painted on it — the plan symbol, dropped into a view
    /// that draws everything else as a thing.
    static func pool(_ painter: AxoPainter, object: PlanObject, base: Double, coping: Color) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let width = object.transform.width
        let depth = object.transform.height
        let walk = min(0.9, min(width, depth) * 0.16)
        let copingZ = base + 0.16
        let waterZ = base - 0.28

        func inset(_ amount: Double) -> [Point] {
            corners.map { corner in
                Point(
                    x: corner.x + (corner.x >= centre.x ? -amount : amount),
                    y: corner.y + (corner.y >= centre.y ? -amount : amount)
                )
            }
        }

        // Coping: a paved ring, drawn as four trapezoids so the water sits in
        // a hole rather than on top of a slab.
        let rim = inset(walk)
        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let innerA = rim[index], innerB = rim[(index + 1) % 4]
            painter.face(
                [(a, copingZ), (b, copingZ), (innerB, copingZ), (innerA, copingZ)],
                fill: coping,
                shade: painter.light.shade(normal: SceneLight.up),
                outline: coping.mix(with: .black, by: 0.25),
                lineWidth: 0.6
            )
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(a, copingZ), (b, copingZ), (b, base), (a, base)], fill: coping, shade: 0.3, outline: nil)
        }

        // Basin walls down to the water, then the water itself.
        let tile = Color(hex: 0x9fd3e4)
        for index in 0..<4 {
            let a = rim[index], b = rim[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            // The *far* sides of the basin: the ones you see the inside of.
            // This was spelled `normal.x + normal.y <= 0` — the fixed
            // camera's visibility test, negated, which is why the sweep that
            // replaced the other ten copies walked straight past it. Turned
            // 90° it tiled the near walls and left the far ones as holes.
            guard !painter.facesCamera(normal) else { continue }
            painter.face([(a, copingZ), (b, copingZ), (b, waterZ), (a, waterZ)], fill: tile, shade: 0.2, outline: nil)
        }
        painter.face(
            rim.map { ($0, waterZ) },
            fill: Color(hex: 0x3fa9d6),
            shade: -0.06,
            outline: Color(hex: 0x2b7fa4),
            lineWidth: 0.8
        )

        guard painter.scale > 3 else { return }
        // A paler shallow end and a few ripples: water, not a blue rectangle.
        let alongX = width >= depth
        for step in 1...3 {
            let t = Double(step) / 4
            let a = alongX ? lerp(rim[0], rim[1], t) : lerp(rim[0], rim[3], t)
            let b = alongX ? lerp(rim[3], rim[2], t) : lerp(rim[1], rim[2], t)
            painter.line((a, waterZ + 0.01), (b, waterZ + 0.01), color: .white.opacity(0.28), width: 1.2)
        }
        // Ladder rails at one end.
        let ladderA = lerp(rim[2], rim[3], 0.35)
        let ladderB = lerp(rim[2], rim[3], 0.5)
        for foot in [ladderA, ladderB] {
            painter.line((foot, waterZ), (foot, copingZ + 0.5), color: Color(hex: 0xd6dde2), width: 1.6)
        }
    }

    /// A timber dock: a planked deck on piles, standing over the water. Same
    /// story as the pool — it was a flat slab with a boat glyph on it.
    static func dock(_ painter: AxoPainter, object: PlanObject, base: Double, deck: Color) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let centre = object.transform.center
        let deckZ = base + 0.55
        let dark = deck.mix(with: .black, by: 0.3)

        // Piles first, so the deck lands on them.
        for corner in corners {
            let inset = Point(
                x: corner.x + (centre.x - corner.x) * 0.14,
                y: corner.y + (centre.y - corner.y) * 0.14
            )
            painter.line((inset, base - 0.6), (inset, deckZ), color: dark, width: max(1.6, CGFloat(0.24 * painter.scale)))
        }

        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let normal = SceneLight.wallNormal(from: a, to: b, about: centre)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(a, deckZ), (b, deckZ), (b, deckZ - 0.18), (a, deckZ - 0.18)], fill: dark, shade: 0.1, outline: nil)
        }
        painter.face(
            corners.map { ($0, deckZ) },
            fill: deck,
            shade: painter.light.shade(normal: SceneLight.up),
            outline: dark,
            lineWidth: 0.7,
            material: .plank,
            seed: object.id
        )
    }

    /// One span of fence rail. Split out from the posts so both can be sorted
    /// into the scene's own depth order: drawing every fence in one pass
    /// before the buildings meant a fence nearer the camera than a building
    /// was still painted over by it, and the run appeared to vanish into the
    /// wall. Painter's algorithm only works if everything sorts together.
    static func fenceRail(_ painter: AxoPainter, from a: Point, to b: Point, height: Double, color: Color) {
        let dark = color.mix(with: .black, by: 0.3)
        let light = color.mix(with: .white, by: 0.18)
        for railFraction in [0.88, 0.5] {
            painter.line((a, height * railFraction), (b, height * railFraction), color: dark, width: 1)
            painter.line((a, height * railFraction + 0.06), (b, height * railFraction + 0.06), color: light, width: 1.6)
        }
    }

    /// One post. A box once there is room for it: a fence runs right around
    /// the plot, so it does more than anything else to set the scene's
    /// material, and a hairline reads as a diagram.
    static func fencePost(_ painter: AxoPainter, at position: Point, height: Double, color: Color) {
        guard painter.scale > 4 else {
            painter.line((position, 0), (position, height), color: color, width: 1.4)
            return
        }
        let light = color.mix(with: .white, by: 0.18)
        let half = 0.09
        let quad = [
            Point(x: position.x - half, y: position.y - half),
            Point(x: position.x + half, y: position.y - half),
            Point(x: position.x + half, y: position.y + half),
            Point(x: position.x - half, y: position.y + half),
        ]
        for face in 0..<4 {
            let p = quad[face], q = quad[(face + 1) % 4]
            let normal = SceneLight.wallNormal(from: p, to: q, about: position)
            guard painter.facesCamera(normal) else { continue }
            painter.face([(p, 0), (q, 0), (q, height), (p, height)], fill: color, shade: painter.light.shade(normal: normal), outline: nil)
        }
        painter.face(quad.map { ($0, height) }, fill: light, shade: 0, outline: nil)
    }

    /// Where the posts of a run stand. Spacing is in metres so posts don't
    /// crowd or thin out as the view zooms.
    static func fencePosts(along points: [Point], spacing: Double = 2.2) -> [Point] {
        guard points.count > 1 else { return [] }
        var positions: [Point] = []
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let length = distance(a, b)
            let steps = max(1, Int(length / spacing))
            for step in 0..<steps {
                positions.append(lerp(a, b, Double(step) / Double(steps)))
            }
        }
        positions.append(points[points.count - 1])
        return positions
    }
}
