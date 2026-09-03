import Foundation

/// Placement of one object: a centre, a size, and a rotation. Ported from
/// `src/engine/geometry.ts`.
public struct Transform: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotationDeg: Double

    public init(x: Double, y: Double, width: Double, height: Double, rotationDeg: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotationDeg = rotationDeg
    }

    public var center: Point { Point(x: x, y: y) }

    /// The four corners in world space, in the order the resize handles use:
    /// top-left, top-right, bottom-right, bottom-left in the object's own
    /// frame.
    public var corners: [Point] {
        let hw = width / 2
        let hh = height / 2
        let rad = rotationDeg * .pi / 180
        let cos = Foundation.cos(rad)
        let sin = Foundation.sin(rad)
        return [
            Point(x: -hw, y: -hh),
            Point(x: hw, y: -hh),
            Point(x: hw, y: hh),
            Point(x: -hw, y: hh),
        ].map { Point(x: x + $0.x * cos - $0.y * sin, y: y + $0.x * sin + $0.y * cos) }
    }

    /// The axis-aligned box around this object. Exact for the axis-aligned
    /// rotations the generator produces, and a conservative over-estimate for
    /// anything else — which is why overlap checks pair it with an exact test
    /// rather than trusting it alone.
    public var aabb: Rect {
        let rotated = rotationDeg.truncatingRemainder(dividingBy: 180) != 0
        let w = rotated ? height : width
        let h = rotated ? width : height
        // minX/maxX and minY/maxY independently, matching TypeScript's
        // `{ minX: t.x-w/2, maxX: t.x+w/2, ... }` — see Rect's doc comment on
        // why this can't go through the width/height convenience.
        return Rect(minX: x - w / 2, minY: y - h / 2, maxX: x + w / 2, maxY: y + h / 2)
    }
}

extension Rect {
    /// `margin` expands the receiver only, matching the asymmetry the
    /// TypeScript separation checks rely on.
    public func overlaps(_ other: Rect, margin: Double = 0) -> Bool {
        minX - margin < other.maxX
            && maxX + margin > other.minX
            && minY - margin < other.maxY
            && maxY + margin > other.minY
    }

    /// The closest point of this box to `target`; lands on the boundary for a
    /// point outside, so a path anchors to a building's edge rather than
    /// running into its centre.
    public func nearestPoint(to target: Point) -> Point {
        Point(x: clamp(target.x, minX, maxX), y: clamp(target.y, minY, maxY))
    }
}

public func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    max(lower, min(upper, value))
}

/// Resizes a possibly-rotated rect by dragging one corner while the
/// diagonally opposite corner stays put in world space. `cornerSign` is the
/// ±1 signature of the dragged corner in the object's own frame.
///
/// Diverges from `src/engine/geometry.ts`, which offsets the new centre by
/// `-cornerSign` and so walks away from the dragged corner instead of toward
/// it: dragging the bottom-right of an 8×4 at (10,10) out to (20,16) lands
/// the rect at corners (-8,0)…(6,8), flinging it up and left while the
/// "fixed" corner becomes the opposite one. No test covers it — see
/// BACKLOG.md.
public func resizeFromCorner(
    fixedCorner: Point,
    cornerSign: Point,
    rotationDeg: Double,
    pointer: Point,
    minWidth: Double,
    minHeight: Double
) -> Transform {
    let rad = rotationDeg * .pi / 180
    let inverseCos = cos(-rad)
    let inverseSin = sin(-rad)
    let dx = pointer.x - fixedCorner.x
    let dy = pointer.y - fixedCorner.y
    let localX = dx * inverseCos - dy * inverseSin
    let localY = dx * inverseSin + dy * inverseCos

    let width = max(minWidth, abs(localX))
    let height = max(minHeight, abs(localY))

    // The centre sits half a diagonal from the fixed corner, along the
    // direction of the corner being dragged, rotated back into world space.
    let offsetX = cornerSign.x * width / 2
    let offsetY = cornerSign.y * height / 2
    let forwardCos = cos(rad)
    let forwardSin = sin(rad)

    return Transform(
        x: fixedCorner.x + offsetX * forwardCos - offsetY * forwardSin,
        y: fixedCorner.y + offsetX * forwardSin + offsetY * forwardCos,
        width: width,
        height: height,
        rotationDeg: rotationDeg
    )
}
