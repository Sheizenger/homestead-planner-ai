import Foundation

/// `hypot` rather than a naive `sqrt` of squares, matching the `Math.hypot`
/// the TypeScript engine uses: distances feed scoring, and a last-ulp
/// difference can flip a comparison and move an object.
public func distance(_ a: Point, _ b: Point) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

/// Polygon predicates and measurements, ported from `src/engine/geometry.ts`.
public enum Polygon {
    /// Ray-casting containment test.
    public static func contains(_ point: Point, polygon: [Point]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i]
            let pj = polygon[j]
            let straddles = (pi.y > point.y) != (pj.y > point.y)
            if straddles, point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Shoelace area, sign-independent so winding direction does not matter.
    public static func area(_ points: [Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// True when the segments cross at a point interior to both. Shared
    /// endpoints and collinear touching are deliberately not intersections:
    /// candidate rectangles routinely sit flush against the plot boundary.
    public static func segmentsIntersect(_ a1: Point, _ a2: Point, _ b1: Point, _ b2: Point) -> Bool {
        func cross(_ o: Point, _ p: Point, _ q: Point) -> Double {
            (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)
        }
        let d1 = cross(b1, b2, a1)
        let d2 = cross(b1, b2, a2)
        let d3 = cross(a1, a2, b1)
        let d4 = cross(a1, a2, b2)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// Corners-inside alone is unsound on a concave boundary: a rectangle can
    /// hold all four corners inside an L while bridging straight across the
    /// missing notch. Edge crossings catch that case.
    public static func contains(_ transform: Transform, polygon: [Point]) -> Bool {
        let corners = transform.corners
        guard corners.allSatisfy({ contains($0, polygon: polygon) }) else { return false }
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            for j in polygon.indices where segmentsIntersect(a, b, polygon[j], polygon[(j + 1) % polygon.count]) {
                return false
            }
        }
        return true
    }

    /// Closest point to `p` on the closed segment `a`–`b`.
    public static func project(_ p: Point, onto a: Point, _ b: Point) -> Point {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return a }
        let t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared, 0, 1)
        return Point(x: a.x + abx * t, y: a.y + aby * t)
    }

    /// Distance from a point to the nearest edge — a setback measurement, not
    /// a containment test. An empty polygon has no boundary to measure to.
    public static func distanceToBoundary(_ p: Point, polygon: [Point]) -> Double? {
        guard !polygon.isEmpty else { return nil }
        var smallest = Double.infinity
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            smallest = min(smallest, distance(p, project(p, onto: a, b)))
        }
        return smallest
    }

    /// Sutherland–Hodgman clip of any polygon against an axis-aligned box.
    /// Keeps a bounds-derived shape — the waterfront strip, say — from
    /// spilling outside a plot whose boundary is not a plain rectangle.
    public static func clip(_ subject: [Point], to box: Rect) -> [Point] {
        let edges: [(Point, Point)] = [
            (Point(x: box.minX, y: box.minY), Point(x: box.maxX, y: box.minY)),
            (Point(x: box.maxX, y: box.minY), Point(x: box.maxX, y: box.maxY)),
            (Point(x: box.maxX, y: box.maxY), Point(x: box.minX, y: box.maxY)),
            (Point(x: box.minX, y: box.maxY), Point(x: box.minX, y: box.minY)),
        ]

        var output = subject
        for (e1, e2) in edges {
            if output.isEmpty { break }
            let input = output
            output = []

            func isInside(_ p: Point) -> Bool {
                (e2.x - e1.x) * (p.y - e1.y) - (e2.y - e1.y) * (p.x - e1.x) >= 0
            }
            func intersection(_ p: Point, _ q: Point) -> Point {
                let a1 = e2.x - e1.x, a2 = e2.y - e1.y
                let b1 = q.x - p.x, b2 = q.y - p.y
                let denominator = a1 * b2 - a2 * b1
                guard abs(denominator) >= 1e-9 else { return p }
                let t = ((p.x - e1.x) * b2 - (p.y - e1.y) * b1) / denominator
                return Point(x: e1.x + a1 * t, y: e1.y + a2 * t)
            }

            for i in input.indices {
                let current = input[i]
                let previous = input[(i - 1 + input.count) % input.count]
                if isInside(current) {
                    if !isInside(previous) { output.append(intersection(previous, current)) }
                    output.append(current)
                } else if isInside(previous) {
                    output.append(intersection(previous, current))
                }
            }
        }
        return output
    }
}
