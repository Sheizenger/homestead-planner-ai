import Foundation

/// Which corner of the rectangle is cut away to form an L-shaped plot.
/// `+y` runs south, matching the convention the rest of the engine uses.
public enum PlotCorner: String, CaseIterable, Codable, Sendable {
    case nw, ne, sw, se
}

public enum PlotShape {
    public static func rectangle(width: Double, height: Double) -> [Point] {
        [
            Point(x: 0, y: 0),
            Point(x: width, y: 0),
            Point(x: width, y: height),
            Point(x: 0, y: height),
        ]
    }

    /// A six-point L, notching `notchWidth` × `notchHeight` out of one corner.
    ///
    /// Diverges from `src/engine/plotShapes.ts`, which builds the `sw` case
    /// wrong: it removes a `notchWidth` × `height - notchHeight` block from
    /// the *north*-west instead, so a 60×45 plot with a 20×15 notch comes out
    /// at 2100 m² instead of 2400. The web app's tests never exercise that
    /// corner. Fixtures avoid `sw` so this divergence cannot mask a real
    /// porting error — see BACKLOG.md.
    public static func lShape(
        width: Double,
        height: Double,
        notchWidth: Double,
        notchHeight: Double,
        corner: PlotCorner
    ) -> [Point] {
        let nw = max(1, min(notchWidth, width - 1))
        let nh = max(1, min(notchHeight, height - 1))

        switch corner {
        case .nw:
            return [
                Point(x: nw, y: 0),
                Point(x: width, y: 0),
                Point(x: width, y: height),
                Point(x: 0, y: height),
                Point(x: 0, y: nh),
                Point(x: nw, y: nh),
            ]
        case .ne:
            return [
                Point(x: 0, y: 0),
                Point(x: width - nw, y: 0),
                Point(x: width - nw, y: nh),
                Point(x: width, y: nh),
                Point(x: width, y: height),
                Point(x: 0, y: height),
            ]
        case .sw:
            return [
                Point(x: 0, y: 0),
                Point(x: width, y: 0),
                Point(x: width, y: height),
                Point(x: nw, y: height),
                Point(x: nw, y: height - nh),
                Point(x: 0, y: height - nh),
            ]
        case .se:
            return [
                Point(x: 0, y: 0),
                Point(x: width, y: 0),
                Point(x: width, y: height - nh),
                Point(x: width - nw, y: height - nh),
                Point(x: width - nw, y: height),
                Point(x: 0, y: height),
            ]
        }
    }
}

extension PlotShape {
    /// What an existing boundary polygon *is*, recovered from its vertices.
    ///
    /// A document stores the polygon and nothing else — not "the user picked
    /// L-shaped, north-west, 20 by 15" — so an editor reopening a saved plan
    /// has to read those settings back off the geometry. Without this it would
    /// have to assume, and assuming "rectangle" silently squares off an
    /// L-shaped plot the first time someone nudges its width.
    public enum Description: Equatable, Sendable {
        case rectangle
        case lShape(notchWidth: Double, notchHeight: Double, corner: PlotCorner)
        /// Neither shape this type can build — a boundary that came from
        /// somewhere else. Editors should leave it alone rather than round it
        /// to the nearest thing they know how to draw.
        case freeform
    }

    public static func describe(_ boundary: [Point]) -> Description {
        let epsilon = 1e-6
        guard let bounds = Rect(bounding: boundary), bounds.width > 0, bounds.height > 0 else { return .freeform }

        let corners: [(corner: PlotCorner, point: Point)] = [
            (.nw, Point(x: bounds.minX, y: bounds.minY)),
            (.ne, Point(x: bounds.maxX, y: bounds.minY)),
            (.sw, Point(x: bounds.minX, y: bounds.maxY)),
            (.se, Point(x: bounds.maxX, y: bounds.maxY)),
        ]
        func isPresent(_ point: Point) -> Bool {
            boundary.contains { abs($0.x - point.x) < epsilon && abs($0.y - point.y) < epsilon }
        }

        let missing = corners.filter { !isPresent($0.point) }
        if boundary.count == 4, missing.isEmpty { return .rectangle }
        guard boundary.count == 6, missing.count == 1, let cut = missing.first else { return .freeform }

        // `lShape` puts exactly one vertex strictly inside the bounding box —
        // the reflex corner where the notch turns — and its offsets from the
        // cut-away corner are the notch's own width and height.
        guard let reflex = boundary.first(where: {
            $0.x > bounds.minX + epsilon && $0.x < bounds.maxX - epsilon
                && $0.y > bounds.minY + epsilon && $0.y < bounds.maxY - epsilon
        }) else { return .freeform }

        return .lShape(
            notchWidth: abs(reflex.x - cut.point.x),
            notchHeight: abs(reflex.y - cut.point.y),
            corner: cut.corner
        )
    }
}
