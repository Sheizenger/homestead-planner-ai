import Foundation

/// Metres, throughout. The plan is modelled in world units and converted to
/// points only at the moment of drawing.
public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Equatable, Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.init(origin: Point(x: minX, y: minY), size: Size(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var width: Double { size.width }
    public var height: Double { size.height }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
}

extension Rect {
    /// The axis-aligned box enclosing a polygon. An empty polygon has no
    /// bounds, which callers handle rather than receiving a zero rect that
    /// silently reads as a valid box at the origin.
    public init?(bounding polygon: [Point]) {
        guard let first = polygon.first else { return nil }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in polygon.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        self.init(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// JavaScript's `Math.round` breaks halves toward +∞; Swift's `rounded()`
/// breaks them away from zero, so the two disagree on every negative
/// half-integer. The planner rounds coordinates that can be negative, so the
/// port uses this rather than `rounded()`.
public func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}
