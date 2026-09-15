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

struct AxoPainter {
    let context: GraphicsContext
    /// World point at elevation z → screen.
    let project: (Point, Double) -> CGPoint
    let scale: Double

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
        context.fill(shape, with: .color(fill))
        if shade > 0 { context.fill(shape, with: .color(.black.opacity(shade))) }
        if shade < 0 { context.fill(shape, with: .color(.white.opacity(-shade))) }
        if let outline { context.stroke(shape, with: .color(outline), lineWidth: lineWidth) }
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
                context.stroke(path, with: .color(ink), lineWidth: lineWidth)
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
                context.stroke(path, with: .color(ink), lineWidth: material == .board ? 0.9 : lineWidth)
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
                    context.stroke(path, with: .color(ink), lineWidth: 0.5)
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
            context.fill(streak, with: .color(.white.opacity(0.16)))
        default:
            break
        }
    }

    func line(_ a: (Point, Double), _ b: (Point, Double), color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: project(a.0, a.1))
        path.addLine(to: project(b.0, b.1))
        context.stroke(path, with: .color(color), lineWidth: width)
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
        let rx = CGFloat(radius * 1.414 * Axonometry.cosA * scale)
        let ry = CGFloat(radius * 1.414 * Axonometry.sinA * scale)
        guard rx > 1 else { return }

        let bottom = project(center, from)
        let top = project(center, to)

        var body = Path()
        body.move(to: CGPoint(x: bottom.x - rx, y: bottom.y))
        body.addLine(to: CGPoint(x: top.x - rx, y: top.y))
        body.addLine(to: CGPoint(x: top.x + rx, y: top.y))
        body.addLine(to: CGPoint(x: bottom.x + rx, y: bottom.y))
        body.closeSubpath()
        context.fill(body, with: .color(fill))
        context.fill(body, with: .color(.black.opacity(shade)))

        let bottomCap = Path(ellipseIn: CGRect(x: bottom.x - rx, y: bottom.y - ry, width: rx * 2, height: ry * 2))
        context.fill(bottomCap, with: .color(fill))
        context.fill(bottomCap, with: .color(.black.opacity(shade)))

        let topCap = Path(ellipseIn: CGRect(x: top.x - rx, y: top.y - ry, width: rx * 2, height: ry * 2))
        context.fill(topCap, with: .color(fill))
        context.fill(topCap, with: .color(.white.opacity(0.12)))
        context.stroke(topCap, with: .color(outline), lineWidth: 0.8)
        context.stroke(body, with: .color(outline), lineWidth: 0.8)

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
            context.fill(shell, with: .color(fill))
            context.fill(shell, with: .color(.white.opacity(0.10)))
            context.stroke(shell, with: .color(outline), lineWidth: 0.8)
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

        // Walls, far ones first so near ones paint over them. Each takes its
        // tone from where the sun is rather than from its draw order, so two
        // buildings at right angles agree about which side is lit.
        let walls = [
            (corners[0], corners[1]), (corners[1], corners[2]),
            (corners[2], corners[3]), (corners[3], corners[0]),
        ].sorted { depth($0) < depth($1) }

        for wallEdge in walls {
            let normal = AxoLight.wallNormal(from: wallEdge.0, to: wallEdge.1)
            painter.face(
                [(wallEdge.0, base), (wallEdge.1, base), (wallEdge.1, eavesZ), (wallEdge.0, eavesZ)],
                fill: wall,
                shade: AxoLight.shade(normal: normal) * (glazed ? 0.5 : 1),
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
        for (index, end) in gableEnds.enumerated() {
            let apex = index == 0 ? ridgeA : ridgeB
            let normal = AxoLight.wallNormal(from: end.0, to: end.1)
            painter.face(
                [(end.0, eavesZ), (end.1, eavesZ), (apex, ridgeZ - deckThickness), (apex, ridgeZ - deckThickness)],
                fill: wall,
                shade: AxoLight.shade(normal: normal) * (glazed ? 0.5 : 1),
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
        for edge in longEdges.sorted(by: { depth($0) < depth($1) }) {
            let normal = AxoLight.roofNormal(from: edge.0, to: edge.1, run: run, rise: rise)
            let flat = (normal.x * normal.x + normal.y * normal.y).squareRoot()
            let outward = flat > 0
                ? Point(x: normal.x / flat * overhang, y: normal.y / flat * overhang)
                : Point(x: 0, y: 0)
            let a = Point(x: edge.0.x + outward.x - along.x, y: edge.0.y + outward.y - along.y)
            let b = Point(x: edge.1.x + outward.x + along.x, y: edge.1.y + outward.y + along.y)
            let eavesDrop = eavesZ - overhang * (rise / max(run, 0.1)) - 0.05

            painter.face(
                [(a, eavesDrop), (b, eavesDrop), (ridgeEnd, ridgeZ), (ridgeStart, ridgeZ)],
                fill: roof,
                shade: AxoLight.shade(normal: normal),
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

        // Ridge cap, which is what makes the two planes read as a pitch.
        painter.line((ridgeStart, ridgeZ), (ridgeEnd, ridgeZ), color: .black.opacity(0.28), width: 1.6)

        if glazed {
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
            openings(painter, object: object, corners: corners, base: base, eavesZ: eavesZ, outline: wallOutline, trim: trim)
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
        ].sorted { depth($0) < depth($1) }
        for wallEdge in walls {
            painter.face(
                [(wallEdge.0, base), (wallEdge.1, base), (wallEdge.1, eavesZ), (wallEdge.0, eavesZ)],
                fill: wall,
                shade: AxoLight.shade(normal: AxoLight.wallNormal(from: wallEdge.0, to: wallEdge.1)),
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
            let normal = AxoLight.wallNormal(from: edge.0, to: edge.1)
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
            let shade = AxoLight.shade(normal: AxoLight.wallNormal(from: end.0, to: end.1))

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

        for edge in longEdges.sorted(by: { depth($0) < depth($1) }) {
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
            let eavesDrop = eavesZ - overhang * (lowerRise / max(knuckleInset, 0.1)) - 0.05
            let lowerNormal = AxoLight.roofNormal(from: edge.0, to: edge.1, run: knuckleInset, rise: lowerRise)
            painter.face(
                [(eavesA, eavesDrop), (eavesB, eavesDrop), (kneeB, knuckleZ), (kneeA, knuckleZ)],
                fill: roof,
                shade: AxoLight.shade(normal: lowerNormal),
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

            let upperNormal = AxoLight.roofNormal(from: kneeA, to: kneeB, run: max(0.1, run - knuckleInset), rise: ridge - knuckle)
            painter.face(
                [(kneeA, knuckleZ), (kneeB, knuckleZ), (ridgeEnd, ridgeZ), (ridgeStart, ridgeZ)],
                fill: roof,
                shade: AxoLight.shade(normal: upperNormal),
                outline: Color.black.opacity(0.2),
                lineWidth: 0.7,
                material: surfaces.roof,
                seed: object.id + "upper"
            )
        }

        painter.line((ridgeStart, ridgeZ), (ridgeEnd, ridgeZ), color: .black.opacity(0.28), width: 1.6)
        barnDoors(painter, object: object, corners: corners, base: base, eavesZ: eavesZ, trim: trim)
    }

    /// The big sliding door with its diagonal brace. Every barn in every
    /// reference has one, and it is what stops a red box being a red box.
    private static func barnDoors(
        _ painter: AxoPainter,
        object: PlanObject,
        corners: [Point],
        base: Double,
        eavesZ: Double,
        trim: Color
    ) {
        let front = (corners[3], corners[2])
        let width = object.transform.width
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

    private static func depth(_ edge: (Point, Point)) -> Double {
        (edge.0.x + edge.0.y + edge.1.x + edge.1.y) / 2
    }

    /// A door on the south wall and windows either side of it — the south
    /// edge is the engine's own "front", the road side by convention — each
    /// in a trim frame. The frames are not decoration: white trim on a red
    /// barn and on a cream house is a large part of why the references read
    /// at a glance, and a window without one is a blue smudge.
    private static func openings(
        _ painter: AxoPainter,
        object: PlanObject,
        corners: [Point],
        base: Double,
        eavesZ: Double,
        outline: Color,
        trim: Color
    ) {
        let front = (corners[3], corners[2])
        let width = object.transform.width
        guard width * painter.scale > 34, eavesZ - base > 1.6 else { return }

        /// A framed panel on the front wall: trim behind, opening in front.
        func panel(from: Double, to: Double, bottom: Double, top: Double, fill: Color, frame: Double) {
            let outerA = lerp(front.0, front.1, max(0, from - frame / width))
            let outerB = lerp(front.0, front.1, min(1, to + frame / width))
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

        let wallHeight = eavesZ - base
        let doorHeight = min(2.1, wallHeight * 0.8)
        let doorHalf = min(0.45, width * 0.06) / width
        panel(
            from: 0.5 - doorHalf, to: 0.5 + doorHalf,
            bottom: base, top: base + doorHeight,
            fill: Color(hex: 0x5a3f2c), frame: 0.12
        )
        // A doorstep, which is what stops a door looking painted on.
        let stepA = lerp(front.0, front.1, 0.5 - doorHalf * 1.4)
        let stepB = lerp(front.0, front.1, 0.5 + doorHalf * 1.4)
        painter.line((stepA, base + 0.06), (stepB, base + 0.06), color: trim, width: max(1.4, CGFloat(0.22 * painter.scale)))

        guard width * painter.scale > 60 else { return }
        let sillZ = base + wallHeight * 0.4
        let headZ = base + wallHeight * 0.76
        for fraction in [0.22, 0.78] {
            panel(
                from: fraction - 0.08, to: fraction + 0.08,
                bottom: sillZ, top: headZ,
                fill: Color(hex: 0x86b4cf), frame: 0.1
            )
            // One glazing bar and a highlight streak: a pane, not a blue hole.
            let centre = lerp(front.0, front.1, fraction)
            painter.line((centre, sillZ), (centre, headZ), color: trim.opacity(0.85), width: 0.9)
            let midZ = (sillZ + headZ) / 2
            let a = lerp(front.0, front.1, fraction - 0.08)
            let b = lerp(front.0, front.1, fraction + 0.08)
            painter.line((a, midZ), (b, midZ), color: trim.opacity(0.85), width: 0.9)
        }
    }

    /// Two beds of seedlings running the length of the house, with a walkway
    /// between them — the arrangement every reference greenhouse has.
    private static func greenhouseInterior(_ painter: AxoPainter, object: PlanObject, base: Double, alongX: Bool) {
        let corners = object.transform.corners
        guard corners.count == 4, painter.scale > 2 else { return }
        let soil = Color(hex: 0x6f4a30)
        let leaf = Color(hex: 0x5fa341)

        for fraction in [0.26, 0.74] {
            let (a, b): (Point, Point) = alongX
                ? (lerp(corners[0], corners[3], fraction), lerp(corners[1], corners[2], fraction))
                : (lerp(corners[0], corners[1], fraction), lerp(corners[3], corners[2], fraction))
            let inner: [(Point, Double)] = [
                (lerp(a, b, 0.08), base + 0.3),
                (lerp(b, a, 0.08), base + 0.3),
                (lerp(b, a, 0.08), base),
                (lerp(a, b, 0.08), base),
            ]
            painter.face(inner, fill: soil, shade: 0.1, outline: nil)

            let count = max(3, min(14, Int(distance(a, b) / 0.8)))
            for index in 0...count {
                let t = Double(index) / Double(count)
                let at = lerp(lerp(a, b, 0.08), lerp(b, a, 0.08), t)
                let top = painter.project(at, base + 0.72)
                let root = painter.project(at, base + 0.3)
                painter.context.stroke(
                    Path { path in
                        path.move(to: root)
                        path.addLine(to: top)
                    },
                    with: .color(leaf),
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

        // The bed stands slightly proud of the grass, with its own cut sides.
        for index in 0..<4 {
            let a = corners[index], b = corners[(index + 1) % 4]
            let normal = AxoLight.wallNormal(from: a, to: b)
            guard normal.x + normal.y > 0 else { continue }
            painter.face(
                [(a, bedZ), (b, bedZ), (b, base), (a, base)],
                fill: tilledSoil,
                shade: AxoLight.shade(normal: normal),
                outline: nil
            )
        }
        painter.face(
            corners.map { ($0, bedZ) },
            fill: tilledSoil,
            shade: AxoLight.shade(normal: AxoLight.up),
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
                    painter.context.stroke(
                        Path { path in
                            path.move(to: root)
                            path.addLine(to: top)
                        },
                        with: .color(leafDark),
                        lineWidth: max(1, radius * 0.3)
                    )
                    painter.context.fill(
                        Path(ellipseIn: CGRect(x: top.x - radius * 0.7, y: top.y - radius * 0.8, width: radius * 1.4, height: radius * 1.5)),
                        with: .color(leaf)
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
                    painter.context.fill(
                        Path(ellipseIn: rect),
                        with: .color(lobe == -1 ? leafLight : (lobe == 1 ? leafDark : leaf))
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
                let rx = CGFloat(r * 1.414 * Axonometry.cosA * painter.scale)
                let ry = CGFloat(r * 1.414 * Axonometry.sinA * painter.scale)
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
                painter.context.fill(cone, with: .color(tier == 0 ? dark : (tier == 1 ? mid : light)))
                painter.context.stroke(cone, with: .color(outline.opacity(0.45)), lineWidth: 0.6)
            }
            return
        }

        // Deciduous: a cluster of lobes around the crown centre, drawn back
        // to front so the lit ones on the sun side end up on top.
        let crownZ = height - radius * 0.45
        let lobeCount = painter.scale > 2.5 ? 7 : 4
        var lobes: [(offset: CGPoint, radius: CGFloat, tone: Color)] = []
        let unit = CGFloat(radius * 1.414 * Axonometry.cosA * painter.scale)
        guard unit > 2 else {
            let centre = painter.project(position, crownZ)
            let rect = CGRect(x: centre.x - unit, y: centre.y - unit * 0.92, width: unit * 2, height: unit * 1.84)
            painter.context.fill(Path(ellipseIn: rect), with: .color(mid))
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
            painter.context.fill(Path(ellipseIn: rect), with: .color(lobe.tone))
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
                shade: AxoLight.shade(normal: (x: 0, y: 0.42, z: 0.91)),
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
            let normal = AxoLight.wallNormal(from: p, to: q)
            guard normal.x + normal.y > 0 else { continue }
            painter.face([(p, 0), (q, 0), (q, height), (p, height)], fill: color, shade: AxoLight.shade(normal: normal), outline: nil)
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
