//
//  ObjectGlyphs.swift
//  Homestead
//
//  Per-type detail drawn inside an object's own frame, ported from the web
//  app's `src/components/canvas/objectGlyphs.tsx`. The point, there and here:
//  every catalog entry gets a representational mark, so a shape reads as
//  "that specific thing" at a glance instead of as a coloured box with a
//  label that may not even fit inside it.
//
//  Coordinates are local metres — origin at the object's centre, +y south,
//  unrotated — exactly like the SVG version's local frame. `Frame` maps them
//  through the object's rotation and the viewport's scale, so a glyph author
//  never deals with screen space.
//

import SwiftUI
import HomesteadEngine

struct GlyphFrame {
    let center: CGPoint
    let scale: Double
    let rotation: Double

    func point(_ x: Double, _ y: Double) -> CGPoint {
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return CGPoint(
            x: center.x + CGFloat((x * cosR - y * sinR) * scale),
            y: center.y + CGFloat((x * sinR + y * cosR) * scale)
        )
    }

    /// Stroke widths in the source are world metres; below about half a point
    /// they stop being visible and just cost time.
    func lineWidth(_ metres: Double) -> CGFloat {
        max(0.4, CGFloat(metres * scale))
    }
}

enum ObjectGlyphs {
    static func draw(_ context: GraphicsContext, object: PlanObject, frame: GlyphFrame, stroke: Color) {
        let w = object.transform.width
        let h = object.transform.height
        // Below this the glyph is noise: the object is a few points across.
        guard w * frame.scale > 14, h * frame.scale > 10 else { return }

        switch object.typeId {
        case "orchard-trees":
            treeGrid(context, w, h, frame, stroke)
        case "berry-rows":
            rowLines(context, w, h, frame, stroke, rows: 4, dashed: true)
        case "vineyard":
            rowLines(context, w, h, frame, stroke, rows: 6, dashed: false)
        case "potato-area":
            furrowLines(context, w, h, frame, stroke, dots: .filled)
        case "vegetable-area":
            furrowLines(context, w, h, frame, stroke, dots: .hollow)
        case "grain-field":
            furrowLines(context, w, h, frame, stroke, dots: .none)
        case "raised-beds":
            bedGrid(context, w, h, frame, stroke)
        case "greenhouse":
            glassGrid(context, w, h, frame, stroke)
        case "solar-array":
            panelGrid(context, w, h, frame, stroke)
        case "well", "water-tank", "rainwater-cistern":
            rings(context, min(w, h) / 2, frame, stroke, count: object.typeId == "well" ? 2 : 3)
        case "pump", "battery-room", "inverter-room", "generator":
            boltMark(context, w, h, frame, stroke)
        case "septic":
            septicLids(context, w, h, frame, stroke)
        case "compost":
            compostMound(context, w, h, frame, stroke)
        case "pool":
            poolIcon(context, w, h, frame, stroke)
        case "patio":
            patioSet(context, w, h, frame, stroke)
        case "goat-paddock":
            pastureHatch(context, w, h, frame, stroke)
        case "poultry-coop":
            coopRun(context, w, h, frame, stroke)
        default:
            let withDoor = ["house", "house-l", "shed", "barn", "workshop", "garage", "banya"].contains(object.typeId)
            roofLines(context, w, h, frame, stroke, withDoor: withDoor)
        }
    }

    // MARK: - Buildings

    /// The architectural roof-plan symbol: a ridge along the longer axis with
    /// four hips sloping to the corners — an actual pitched roof rather than
    /// a corner-to-centre X.
    private static func roofLines(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color, withDoor: Bool) {
        let hw = w / 2, hh = h / 2
        let horizontal = w >= h
        let ridgeHalf = max(0, (horizontal ? hw : hh) - min(hw, hh) * 0.9)
        let ridgeA = horizontal ? (-ridgeHalf, 0.0) : (0.0, -ridgeHalf)
        let ridgeB = horizontal ? (ridgeHalf, 0.0) : (0.0, ridgeHalf)

        var ridge = Path()
        ridge.move(to: frame.point(ridgeA.0, ridgeA.1))
        ridge.addLine(to: frame.point(ridgeB.0, ridgeB.1))
        context.stroke(ridge, with: .color(stroke.opacity(0.65)), lineWidth: frame.lineWidth(0.09))

        var hips = Path()
        for corner in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
            let anchor = (horizontal ? corner.0 < 0 : corner.1 < 0) ? ridgeA : ridgeB
            hips.move(to: frame.point(corner.0, corner.1))
            hips.addLine(to: frame.point(anchor.0, anchor.1))
        }
        context.stroke(hips, with: .color(stroke.opacity(0.65)), lineWidth: frame.lineWidth(0.06))

        if withDoor, w > 3 {
            var door = Path()
            door.move(to: frame.point(-0.5, hh))
            door.addLine(to: frame.point(0.5, hh))
            context.stroke(door, with: .color(stroke.opacity(0.9)), lineWidth: frame.lineWidth(0.35))
        }
    }

    // MARK: - Growing areas

    private static func treeGrid(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let spacing = 2.6, margin = 1.1
        let cols = min(6, max(1, Int((w - margin * 2) / spacing) + 1))
        let rows = min(6, max(1, Int((h - margin * 2) / spacing) + 1))
        let canopyR = min(0.85, spacing / 2.6)

        for r in 0..<rows {
            for c in 0..<cols {
                let x = cols == 1
                    ? 0.0
                    : -w / 2 + margin + Double(c) * (w - margin * 2) / Double(cols - 1)
                let y = rows == 1
                    ? 0.0
                    : -h / 2 + margin + Double(r) * (h - margin * 2) / Double(rows - 1)
                tree(context, x, y, canopyR, frame, stroke)
            }
        }
    }

    /// Trunk plus a three-lobe crown — reads as a tree in plan view, where a
    /// single flat dot reads as a manhole.
    private static func tree(_ context: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ frame: GlyphFrame, _ stroke: Color) {
        var trunk = Path()
        trunk.move(to: frame.point(x, y + r * 0.3))
        trunk.addLine(to: frame.point(x, y + r * 0.95))
        context.stroke(trunk, with: .color(stroke.opacity(0.75)), lineWidth: frame.lineWidth(0.06))

        for lobe in [(0.0, -r * 0.32, r * 0.72), (-r * 0.42, r * 0.08, r * 0.56), (r * 0.42, r * 0.08, r * 0.56)] {
            let centre = frame.point(x + lobe.0, y + lobe.1)
            let radius = CGFloat(lobe.2 * frame.scale)
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(stroke.opacity(0.32)))
            context.stroke(circle, with: .color(stroke.opacity(0.85)), lineWidth: frame.lineWidth(0.06))
        }
    }

    private static func rowLines(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color, rows: Int, dashed: Bool) {
        let margin = 0.6
        let usableH = h - margin * 2
        guard usableH > 0 else { return }

        var path = Path()
        for i in 0..<rows {
            let y = rows == 1
                ? 0.0
                : -h / 2 + margin + Double(i) * usableH / Double(rows - 1)
            path.move(to: frame.point(-w / 2 + margin, y))
            path.addLine(to: frame.point(w / 2 - margin, y))
        }
        let style = StrokeStyle(lineWidth: frame.lineWidth(0.08), dash: dashed ? [frame.lineWidth(0.4), frame.lineWidth(0.3)] : [])
        context.stroke(path, with: .color(stroke.opacity(0.65)), style: style)
    }

    private enum FurrowDots { case none, filled, hollow }

    private static func furrowLines(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color, dots: FurrowDots) {
        let spacing = 1.1, margin = 0.5
        let usableH = h - margin * 2
        let usableW = w - margin * 2
        guard usableH > 0, usableW > 0 else { return }
        let count = max(2, Int(usableH / spacing))

        var path = Path()
        for i in 0...count {
            let y = -h / 2 + margin + Double(i) * usableH / Double(count)
            path.move(to: frame.point(-w / 2 + margin, y))
            path.addLine(to: frame.point(w / 2 - margin, y))
        }
        context.stroke(path, with: .color(stroke.opacity(0.45)), lineWidth: frame.lineWidth(0.05))

        guard dots != .none else { return }
        let dotCols = max(1, Int(usableW / 1.0))
        let radius = CGFloat((dots == .filled ? 0.1 : 0.13) * frame.scale)
        guard radius > 0.6 else { return }

        for row in 0..<count {
            let yTop = -h / 2 + margin + Double(row) * usableH / Double(count)
            let yMid = yTop + usableH / Double(count) / 2
            for col in 0..<dotCols {
                let x = -w / 2 + margin + (Double(col) + 0.5) * usableW / Double(dotCols)
                let centre = frame.point(x, yMid)
                let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                if dots == .filled {
                    context.fill(Path(ellipseIn: rect), with: .color(stroke.opacity(0.4)))
                } else {
                    context.stroke(Path(ellipseIn: rect), with: .color(stroke.opacity(0.6)), lineWidth: frame.lineWidth(0.04))
                }
            }
        }
    }

    private static func bedGrid(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let bedWidth = 1.2, gap = 0.4
        let count = max(1, Int((w + gap) / (bedWidth + gap)))
        let total = Double(count) * bedWidth + Double(count - 1) * gap
        var path = Path()
        for i in 0..<count {
            let x0 = -total / 2 + Double(i) * (bedWidth + gap)
            path.addLines([
                frame.point(x0, -h / 2 + 0.4),
                frame.point(x0 + bedWidth, -h / 2 + 0.4),
                frame.point(x0 + bedWidth, h / 2 - 0.4),
                frame.point(x0, h / 2 - 0.4),
            ])
            path.closeSubpath()
        }
        context.fill(path, with: .color(stroke.opacity(0.16)))
        context.stroke(path, with: .color(stroke.opacity(0.65)), lineWidth: frame.lineWidth(0.06))
    }

    private static func glassGrid(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let spacing = 1.3
        let cols = max(1, Int((w / spacing).rounded()))
        let rows = max(1, Int((h / spacing).rounded()))

        var path = Path()
        for c in 1..<max(2, cols) {
            let x = -w / 2 + Double(c) * w / Double(cols)
            path.move(to: frame.point(x, -h / 2))
            path.addLine(to: frame.point(x, h / 2))
        }
        for r in 1..<max(2, rows) {
            let y = -h / 2 + Double(r) * h / Double(rows)
            path.move(to: frame.point(-w / 2, y))
            path.addLine(to: frame.point(w / 2, y))
        }
        context.stroke(path, with: .color(stroke.opacity(0.55)), lineWidth: frame.lineWidth(0.05))

        // The ridge line along the top, which is what says "glasshouse" rather
        // than "tiled floor".
        var ridge = Path()
        ridge.move(to: frame.point(-w / 2, -h / 2 + 0.6))
        ridge.addQuadCurve(to: frame.point(w / 2, -h / 2 + 0.6), control: frame.point(0, -h / 2 - 0.3))
        context.stroke(ridge, with: .color(stroke.opacity(0.7)), lineWidth: frame.lineWidth(0.08))
    }

    private static func panelGrid(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let cols = max(2, Int((w / 1.6).rounded()))
        let rows = max(1, Int((h / 1.6).rounded()))
        let gap = 0.15
        let cellW = (w - gap * Double(cols + 1)) / Double(cols)
        let cellH = (h - gap * Double(rows + 1)) / Double(rows)
        guard cellW > 0.2, cellH > 0.2 else { return }

        var path = Path()
        for r in 0..<rows {
            for c in 0..<cols {
                let x = -w / 2 + gap + Double(c) * (cellW + gap)
                let y = -h / 2 + gap + Double(r) * (cellH + gap)
                path.addLines([
                    frame.point(x, y),
                    frame.point(x + cellW, y),
                    frame.point(x + cellW, y + cellH),
                    frame.point(x, y + cellH),
                ])
                path.closeSubpath()
            }
        }
        context.fill(path, with: .color(stroke.opacity(0.12)))
        context.stroke(path, with: .color(stroke.opacity(0.8)), lineWidth: frame.lineWidth(0.06))
    }

    // MARK: - Utilities and water

    private static func rings(_ context: GraphicsContext, _ radius: Double, _ frame: GlyphFrame, _ stroke: Color, count: Int) {
        for i in 0..<count {
            let r = radius * (1 - Double(i) * 0.28) * 0.8
            guard r > 0 else { continue }
            let centre = frame.point(0, 0)
            let screenR = CGFloat(r * frame.scale)
            let rect = CGRect(x: centre.x - screenR, y: centre.y - screenR, width: screenR * 2, height: screenR * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(stroke.opacity(0.75)), lineWidth: frame.lineWidth(0.08))
        }
    }

    private static func boltMark(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let s = min(w, h) * 0.32
        var path = Path()
        path.addLines([
            frame.point(s * 0.25, -s),
            frame.point(-s * 0.45, s * 0.15),
            frame.point(0, s * 0.15),
            frame.point(-s * 0.25, s),
            frame.point(s * 0.45, -s * 0.15),
            frame.point(0, -s * 0.15),
        ])
        path.closeSubpath()
        context.fill(path, with: .color(stroke.opacity(0.75)))
    }

    private static func septicLids(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let r = min(w, h) * 0.18
        for offset in [-w * 0.22, w * 0.22] {
            let centre = frame.point(offset, 0)
            let screenR = CGFloat(r * frame.scale)
            let rect = CGRect(x: centre.x - screenR, y: centre.y - screenR, width: screenR * 2, height: screenR * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(stroke.opacity(0.75)), lineWidth: frame.lineWidth(0.07))
        }
    }

    private static func compostMound(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        var path = Path()
        path.move(to: frame.point(-w / 2 + 0.3, h / 2 - 0.3))
        path.addQuadCurve(to: frame.point(w / 2 - 0.3, h / 2 - 0.3), control: frame.point(0, -h / 2 + 0.2))
        context.stroke(path, with: .color(stroke.opacity(0.7)), lineWidth: frame.lineWidth(0.08))
    }

    private static func poolIcon(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        var path = Path()
        let amplitude = h * 0.08
        for row in 0..<2 {
            let y = -h * 0.1 + Double(row) * h * 0.25
            path.move(to: frame.point(-w / 2 + 0.4, y))
            path.addQuadCurve(to: frame.point(0, y), control: frame.point(-w / 4, y - amplitude))
            path.addQuadCurve(to: frame.point(w / 2 - 0.4, y), control: frame.point(w / 4, y + amplitude))
        }
        context.stroke(path, with: .color(stroke.opacity(0.7)), lineWidth: frame.lineWidth(0.1))
    }

    private static func patioSet(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        let r = min(w, h) * 0.16
        let centre = frame.point(0, 0)
        let screenR = CGFloat(r * frame.scale)
        let table = CGRect(x: centre.x - screenR, y: centre.y - screenR, width: screenR * 2, height: screenR * 2)
        context.stroke(Path(ellipseIn: table), with: .color(stroke.opacity(0.75)), lineWidth: frame.lineWidth(0.08))

        let seatR = CGFloat(r * 0.45 * frame.scale)
        guard seatR > 0.5 else { return }
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 2) {
            let seatCentre = frame.point(cos(angle) * r * 1.9, sin(angle) * r * 1.9)
            let rect = CGRect(x: seatCentre.x - seatR, y: seatCentre.y - seatR, width: seatR * 2, height: seatR * 2)
            context.fill(Path(ellipseIn: rect), with: .color(stroke.opacity(0.5)))
        }
    }

    // MARK: - Animals

    private static func pastureHatch(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        var path = Path()
        let step = 2.0
        var x = -w / 2 + step
        while x < w / 2 {
            path.move(to: frame.point(x, h / 2 - 0.4))
            path.addLine(to: frame.point(x - min(1.2, h - 0.8), h / 2 - min(1.2, h - 0.8) - 0.4))
            x += step
        }
        context.stroke(path, with: .color(stroke.opacity(0.4)), lineWidth: frame.lineWidth(0.07))
    }

    private static func coopRun(_ context: GraphicsContext, _ w: Double, _ h: Double, _ frame: GlyphFrame, _ stroke: Color) {
        roofLines(context, w * 0.55, h, GlyphFrame(center: frame.point(-w * 0.22, 0), scale: frame.scale, rotation: frame.rotation), stroke, withDoor: false)

        var mesh = Path()
        var x = 0.2
        while x < w / 2 - 0.2 {
            mesh.move(to: frame.point(x, -h / 2 + 0.3))
            mesh.addLine(to: frame.point(x, h / 2 - 0.3))
            x += 0.5
        }
        context.stroke(mesh, with: .color(stroke.opacity(0.45)), lineWidth: frame.lineWidth(0.05))
    }
}
