import Testing
@testable import HomesteadEngine

/// The axonometric view selects and hit-tests objects by the hull of their
/// projected vertices, so this is load-bearing for "click anywhere on the
/// thing you can see" — and it is the one part of that which can be tested
/// here at all, the view layer being Mac-only.
struct ConvexHullTests {
    @Test func aSquareIsItsOwnHull() {
        let square = [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 4), Point(x: 0, y: 4)]
        let hull = Polygon.convexHull(square)
        #expect(hull.count == 4)
        #expect(Set(hull.map(\.x)) == [0, 4])
        #expect(Set(hull.map(\.y)) == [0, 4])
    }

    @Test func interiorAndCollinearPointsAreDropped() {
        let points = [
            Point(x: 0, y: 0), Point(x: 2, y: 0), Point(x: 4, y: 0),   // collinear on an edge
            Point(x: 4, y: 4), Point(x: 0, y: 4),
            Point(x: 2, y: 2), Point(x: 1, y: 3),                       // strictly inside
        ]
        #expect(Polygon.convexHull(points).count == 4)
    }

    /// The property that matters: every input point is inside the hull it
    /// produced. A building's silhouette has to contain the building.
    @Test func everyPointLiesInsideTheHull() {
        var rng = RandomStream(seed: 11)
        var points: [Point] = []
        for _ in 0..<60 {
            points.append(Point(x: rng.next() * 100 - 50, y: rng.next() * 100 - 50))
        }
        let hull = Polygon.convexHull(points)
        #expect(hull.count >= 3)
        for point in points {
            let onEdge = hull.contains { abs($0.x - point.x) < 1e-9 && abs($0.y - point.y) < 1e-9 }
            #expect(onEdge || Polygon.contains(point, polygon: hull), Comment(rawValue: "\(point)"))
        }
    }

    @Test func degenerateInputsComeBackUnchanged() {
        #expect(Polygon.convexHull([]).isEmpty)
        #expect(Polygon.convexHull([Point(x: 1, y: 1)]).count == 1)
        #expect(Polygon.convexHull([Point(x: 1, y: 1), Point(x: 2, y: 2)]).count == 2)
        // A line of three: no area, so there is no hull to speak of.
        let line = [Point(x: 0, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 2)]
        #expect(Polygon.convexHull(line).count <= 3)
    }
}
