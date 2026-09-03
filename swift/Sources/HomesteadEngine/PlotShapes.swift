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
