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

    /// The wall that looks most nearly at `target`, as the pair of base
    /// corners it runs between.
    ///
    /// This is where a door goes. A garage door has to face the gate — a car
    /// arrives from the road and leaves toward it — and picking the wall by
    /// anything else (the nearest path node, say, which can be beside or
    /// behind the building) puts it on a blank elevation facing a fence.
    /// Geometry, so it lives here where it can be tested, rather than in the
    /// view that draws the door.
    public func wall(facing target: Point) -> (Point, Point) {
        let corners = self.corners
        guard corners.count == 4 else { return (center, center) }
        let toTarget = (x: target.x - x, y: target.y - y)
        let length = (toTarget.x * toTarget.x + toTarget.y * toTarget.y).squareRoot()
        guard length > 0 else { return (corners[3], corners[2]) }

        var best = (corners[3], corners[2])
        var bestAlignment = -Double.infinity
        for index in 0..<4 {
            let a = corners[index]
            let b = corners[(index + 1) % 4]
            // Outward normal resolved against the centre, so it does not
            // depend on which way round the edge is listed.
            var normal = (x: b.y - a.y, y: -(b.x - a.x))
            let midX = (a.x + b.x) / 2 - x
            let midY = (a.y + b.y) / 2 - y
            if normal.x * midX + normal.y * midY < 0 { normal = (x: -normal.x, y: -normal.y) }

            let alignment = (normal.x * toTarget.x + normal.y * toTarget.y) / length
            if alignment > bestAlignment {
                bestAlignment = alignment
                best = (a, b)
            }
        }
        return best
    }

    /// The axis-aligned box `transformAabb` in the TypeScript engine
    /// computes: exact for the axis-aligned rotations the generator ever
    /// produces (0/90/180/270°), by swapping width and height rather than
    /// measuring the rotated corners. At any other angle it is not a real
    /// bounding box and is not conservative either way — a 45°-rotated
    /// square's diagonal reaches past every edge of this box, so it can
    /// *under*-report the true extent. Kept faithful to the original for the
    /// engine's own overlap/violation checks, which only ever see axis-aligned
    /// input; anything working with a freely-rotated `Transform` (hit-testing
    /// a canvas the user has rotated something on) needs a true box instead —
    /// `Rect(bounding: transform.corners)`.
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
