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

/// Ported from the TypeScript `Bounds` type, and deliberately storing all
/// four edges rather than an origin + size: `maxY` derived as `minY +
/// height` is not bit-identical to an independently computed `y + h/2`, since
/// floating-point addition isn't associative. `Transform.aabb` and
/// `WaterfrontModel.bounds` both need to reproduce TypeScript's independent
/// min/max expressions exactly, so the type they build has to be able to
/// hold two numbers that don't agree with each other to the last bit of a
/// width — which an origin+size representation cannot represent at all.
public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// Convenience for the (common) case where TypeScript itself derives the
    /// box from a width/height rather than independent edges — safe here
    /// because there's no competing expression it has to match bit-for-bit.
    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.init(minX: minX, minY: minY, maxX: minX + width, maxY: minY + height)
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var midX: Double { minX + width / 2 }
    public var midY: Double { minY + height / 2 }
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
        self.init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}

/// JavaScript's `Math.round` breaks halves toward +∞; Swift's `rounded()`
/// breaks them away from zero, so the two disagree on every negative
/// half-integer. The planner rounds coordinates that can be negative, so the
/// port uses this rather than `rounded()`.
public func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
}
