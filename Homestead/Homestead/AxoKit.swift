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

    func line(_ a: (Point, Double), _ b: (Point, Double), color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: project(a.0, a.1))
        path.addLine(to: project(b.0, b.1))
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    /// A horizontal circle projects to a screen-axis-aligned ellipse under
    /// this projection, so a cylinder is two ellipses plus the strip between
    /// their tangents.
    func cylinder(center: Point, radius: Double, from: Double, to: Double, fill: Color, outline: Color, shade: Double) {
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
        glazed: Bool
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }

        let eavesZ = base + eaves
        let ridgeZ = base + ridge
        let alongX = object.transform.width >= object.transform.height

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

        // Walls, far ones first so near ones paint over them.
        let walls = [
            (corners[0], corners[1]), (corners[1], corners[2]),
            (corners[2], corners[3]), (corners[3], corners[0]),
        ].sorted { depth($0) < depth($1) }

        for (index, wallEdge) in walls.enumerated() {
            let shade = index < 2 ? 0.34 : (index == 2 ? 0.20 : 0.08)
            painter.face(
                [(wallEdge.0, base), (wallEdge.1, base), (wallEdge.1, eavesZ), (wallEdge.0, eavesZ)],
                fill: wall,
                shade: glazed ? shade * 0.5 : shade,
                outline: wallOutline
            )
        }

        // Gable triangles.
        for (index, end) in gableEnds.enumerated() {
            let apex = index == 0 ? ridgeA : ridgeB
            painter.face(
                [(end.0, eavesZ), (end.1, eavesZ), (apex, ridgeZ)],
                fill: wall,
                shade: glazed ? 0.08 : 0.22,
                outline: wallOutline
            )
        }

        // Roof planes: eaves edge up to the ridge. Drawn far side first so
        // the near slope paints over it.
        for (index, edge) in longEdges.sorted(by: { depth($0) < depth($1) }).enumerated() {
            painter.face(
                [(edge.0, eavesZ), (edge.1, eavesZ), (ridgeB, ridgeZ), (ridgeA, ridgeZ)],
                fill: roof,
                shade: index == 0 ? -0.08 : 0.18
            )
        }

        // Ridge line, which is what makes the two planes read as a pitch.
        painter.line((ridgeA, ridgeZ), (ridgeB, ridgeZ), color: .black.opacity(0.25), width: 1)

        if glazed {
            glazingBars(painter, longEdges: longEdges, ridgeA: ridgeA, ridgeB: ridgeB, eavesZ: eavesZ, ridgeZ: ridgeZ, color: wallOutline)
        } else {
            openings(painter, object: object, corners: corners, base: base, eavesZ: eavesZ, outline: wallOutline)
        }
    }

    private static func depth(_ edge: (Point, Point)) -> Double {
        (edge.0.x + edge.0.y + edge.1.x + edge.1.y) / 2
    }

    /// A door on the south wall and windows either side of it — the south
    /// edge is the engine's own "front", the road side by convention.
    private static func openings(
        _ painter: AxoPainter,
        object: PlanObject,
        corners: [Point],
        base: Double,
        eavesZ: Double,
        outline: Color
    ) {
        let front = (corners[3], corners[2])
        let width = object.transform.width
        guard width * painter.scale > 34, eavesZ - base > 1.6 else { return }

        let doorHeight = min(2.1, (eavesZ - base) * 0.8)
        let doorHalf = min(0.45, width * 0.06)
        let centreFraction = 0.5
        let doorA = lerp(front.0, front.1, centreFraction - doorHalf / width)
        let doorB = lerp(front.0, front.1, centreFraction + doorHalf / width)
        painter.face(
            [(doorA, base), (doorB, base), (doorB, base + doorHeight), (doorA, base + doorHeight)],
            fill: .black.opacity(0.45),
            shade: 0,
            outline: outline.opacity(0.7),
            lineWidth: 0.6
        )

        guard width * painter.scale > 60 else { return }
        let sillZ = base + (eavesZ - base) * 0.42
        let headZ = base + (eavesZ - base) * 0.78
        for fraction in [0.22, 0.78] {
            let a = lerp(front.0, front.1, fraction - 0.07)
            let b = lerp(front.0, front.1, fraction + 0.07)
            painter.face(
                [(a, sillZ), (b, sillZ), (b, headZ), (a, headZ)],
                fill: Color(hex: 0x8fb8cc).opacity(0.85),
                shade: 0,
                outline: outline.opacity(0.7),
                lineWidth: 0.6
            )
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

    /// Raised planting beds with crops on them: the strips are what make a
    /// field read as cultivated rather than as a green rectangle.
    static func plantedRows(
        _ painter: AxoPainter,
        object: PlanObject,
        base: Double,
        height: Double,
        soil: Color,
        crop: Color,
        outline: Color
    ) {
        let corners = object.transform.corners
        guard corners.count == 4 else { return }
        let width = object.transform.width
        let depthM = object.transform.height
        let alongX = width >= depthM
        let span = alongX ? depthM : width
        let rowCount = max(2, min(8, Int(span / 1.6)))

        // Bed slab.
        painter.face(corners.map { ($0, base + height * 0.35) }, fill: soil, shade: 0.05, outline: outline, lineWidth: 0.7)

        for index in 0..<rowCount {
            let fraction = (Double(index) + 0.5) / Double(rowCount)
            let (a, b): (Point, Point) = alongX
                ? (lerp(corners[0], corners[3], fraction), lerp(corners[1], corners[2], fraction))
                : (lerp(corners[0], corners[1], fraction), lerp(corners[3], corners[2], fraction))
            let inset = 0.04
            let rowA = lerp(a, b, inset)
            let rowB = lerp(b, a, inset)
            painter.line((rowA, base + height * 0.35), (rowB, base + height * 0.35), color: outline.opacity(0.5), width: 1)

            // A few plants along the row, so it reads as growing.
            let plantCount = max(2, min(7, Int((alongX ? width : depthM) / 2.0)))
            for plant in 0..<plantCount {
                let t = (Double(plant) + 0.5) / Double(plantCount)
                let at = lerp(rowA, rowB, t)
                painter.line((at, base + height * 0.35), (at, base + height), color: crop, width: max(1.2, CGFloat(0.28 * painter.scale)))
            }
        }
    }

    /// Deciduous crown or conifer cone, on a trunk.
    static func tree(_ painter: AxoPainter, at position: Point, height: Double, radius: Double, conifer: Bool, foliage: Color, outline: Color) {
        let trunkTop = height * (conifer ? 0.28 : 0.55)
        painter.line((position, 0), (position, trunkTop), color: Color(hex: 0x6b4f38), width: max(1.2, CGFloat(0.3 * painter.scale)))

        if conifer {
            // Three stacked skirts, widest at the bottom.
            for tier in 0..<3 {
                let t = Double(tier)
                let bottom = trunkTop + (height - trunkTop) * (t / 3)
                let top = trunkTop + (height - trunkTop) * ((t + 1.6) / 3)
                let r = radius * (1 - t * 0.26)
                let rx = CGFloat(r * 1.414 * Axonometry.cosA * painter.scale)
                let ry = CGFloat(r * 1.414 * Axonometry.sinA * painter.scale)
                let baseScreen = painter.project(position, bottom)
                let apex = painter.project(position, top)

                var cone = Path()
                cone.move(to: CGPoint(x: baseScreen.x - rx, y: baseScreen.y))
                cone.addLine(to: apex)
                cone.addLine(to: CGPoint(x: baseScreen.x + rx, y: baseScreen.y))
                cone.addCurve(
                    to: CGPoint(x: baseScreen.x - rx, y: baseScreen.y),
                    control1: CGPoint(x: baseScreen.x + rx * 0.55, y: baseScreen.y + ry * 1.2),
                    control2: CGPoint(x: baseScreen.x - rx * 0.55, y: baseScreen.y + ry * 1.2)
                )
                cone.closeSubpath()
                painter.context.fill(cone, with: .color(foliage))
                painter.context.fill(cone, with: .color(.white.opacity(0.05 * t)))
                painter.context.stroke(cone, with: .color(outline.opacity(0.6)), lineWidth: 0.6)
            }
        } else {
            let crownCentre = painter.project(position, height - radius * 0.6)
            let rx = CGFloat(radius * 1.414 * Axonometry.cosA * painter.scale)
            let ry = rx * 0.92
            let rect = CGRect(x: crownCentre.x - rx, y: crownCentre.y - ry, width: rx * 2, height: ry * 2)
            painter.context.fill(Path(ellipseIn: rect), with: .color(foliage))
            painter.context.fill(
                Path(ellipseIn: rect.insetBy(dx: rx * 0.35, dy: ry * 0.35).offsetBy(dx: -rx * 0.22, dy: -ry * 0.24)),
                with: .color(.white.opacity(0.13))
            )
            painter.context.stroke(Path(ellipseIn: rect), with: .color(outline.opacity(0.6)), lineWidth: 0.7)
        }
    }

    /// Posts and two rails, rather than a line floating at fence height.
    static func fence(_ painter: AxoPainter, points: [Point], height: Double, color: Color) {
        guard points.count > 1 else { return }
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            for railFraction in [0.95, 0.55] {
                painter.line((a, height * railFraction), (b, height * railFraction), color: color.opacity(0.9), width: 1)
            }
        }
        let spacing = max(1.5, 40 / max(painter.scale, 1))
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            let steps = max(1, Int(length / spacing))
            for step in 0...steps {
                let at = lerp(a, b, Double(step) / Double(steps))
                painter.line((at, 0), (at, height), color: color, width: 1.4)
            }
        }
    }
}
