import Foundation

public struct ContourLine: Equatable, Sendable {
    public var elevationM: Double
    public var a: Point
    public var b: Point
}

/// A linear-grade elevation model, ported from `src/engine/elevation.ts`:
/// 0 m at the boundary edge opposite `highEdge`, rising to `dropM` at
/// `highEdge` itself, interpolated linearly between. A coarse stand-in for a
/// survey, not GIS-grade terrain — see AGENTS.md.
public enum ElevationModel {
    public static func elevation(on plot: Plot, at point: Point) -> Double {
        guard let el = plot.elevation, el.dropM > 0, let b = plot.bounds else { return 0 }
        let spanY = max(1e-6, b.height)
        let spanX = max(1e-6, b.width)
        switch el.highEdge {
        case .north: return el.dropM * ((b.maxY - point.y) / spanY)
        case .south: return el.dropM * ((point.y - b.minY) / spanY)
        case .west: return el.dropM * ((b.maxX - point.x) / spanX)
        case .east: return el.dropM * ((point.x - b.minX) / spanX)
        }
    }

    /// Rounds a raw interval up to a "nice" number (1/2/5 × a power of ten)
    /// so contour labels read "2 m", "5 m", "10 m" rather than "3.7 m".
    private static func niceInterval(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10
        return nice * magnitude
    }

    /// Straight lines parallel to the low/high edges, evenly spaced by
    /// elevation and clipped to the plot's bounding box — a fine visual
    /// approximation even on a concave polygon, the same tradeoff already
    /// accepted for the grid lines.
    public static func contourLines(on plot: Plot, targetCount: Int = 5) -> [ContourLine] {
        guard let el = plot.elevation, el.dropM > 0, let bounds = plot.bounds else { return [] }
        let interval = niceInterval(el.dropM / Double(targetCount))
        var lines: [ContourLine] = []
        var level = interval
        while level < el.dropM - 1e-6 {
            let t = level / el.dropM
            let a: Point
            let b: Point
            switch el.highEdge {
            case .north:
                let y = bounds.maxY - t * bounds.height
                a = Point(x: bounds.minX, y: y)
                b = Point(x: bounds.maxX, y: y)
            case .south:
                let y = bounds.minY + t * bounds.height
                a = Point(x: bounds.minX, y: y)
                b = Point(x: bounds.maxX, y: y)
            case .west:
                let x = bounds.maxX - t * bounds.width
                a = Point(x: x, y: bounds.minY)
                b = Point(x: x, y: bounds.maxY)
            case .east:
                let x = bounds.minX + t * bounds.width
                a = Point(x: x, y: bounds.minY)
                b = Point(x: x, y: bounds.maxY)
            }
            lines.append(ContourLine(elevationM: level, a: a, b: b))
            level += interval
        }
        return lines
    }
}
