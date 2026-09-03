import Testing
import Foundation
@testable import HomesteadEngine

// MARK: - Polygons

@Test func areaIgnoresWindingDirection() {
    let square = PlotShape.rectangle(width: 10, height: 4)
    #expect(Polygon.area(square) == 40)
    #expect(Polygon.area(square.reversed()) == 40)
    #expect(Polygon.area([Point(x: 0, y: 0), Point(x: 1, y: 1)]) == 0)
}

@Test func containmentOnAConcaveBoundary() {
    let l = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: .ne)
    #expect(Polygon.contains(Point(x: 10, y: 10), polygon: l))
    // Inside the bounding box, inside the notch, outside the plot.
    #expect(!Polygon.contains(Point(x: 50, y: 5), polygon: l))
    #expect(!Polygon.contains(Point(x: 70, y: 10), polygon: l))
}

/// The case corner-testing alone gets wrong: a thin rect laid diagonally
/// across the L's concave vertex keeps all four corners inside the plot while
/// its long edge crosses the missing bite.
@Test func containmentRejectsARectangleBridgingTheNotch() {
    let l = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: .ne)
    let bridging = Transform(x: 40, y: 15, width: 20, height: 2, rotationDeg: 45)
    #expect(bridging.corners.allSatisfy { Polygon.contains($0, polygon: l) })
    #expect(!Polygon.contains(bridging, polygon: l))

    let clear = Transform(x: 15, y: 25, width: 10, height: 8)
    #expect(Polygon.contains(clear, polygon: l))
}

@Test func segmentsCrossOnlyAtInteriorPoints() {
    let a1 = Point(x: 0, y: 0), a2 = Point(x: 10, y: 10)
    #expect(Polygon.segmentsIntersect(a1, a2, Point(x: 0, y: 10), Point(x: 10, y: 0)))
    #expect(!Polygon.segmentsIntersect(a1, a2, Point(x: 20, y: 0), Point(x: 30, y: 10)))
    // A shared endpoint is not a crossing — candidates sit flush against the
    // plot boundary all the time.
    #expect(!Polygon.segmentsIntersect(a1, a2, a2, Point(x: 20, y: 0)))
}

@Test func clippingKeepsAStripInsideTheBox() {
    let strip = PlotShape.rectangle(width: 40, height: 10)
    let clipped = Polygon.clip(strip, to: Rect(minX: 0, minY: 0, width: 25, height: 30))
    #expect(Polygon.area(clipped) == 250)

    #expect(Polygon.clip(strip, to: Rect(minX: 100, minY: 100, width: 5, height: 5)).isEmpty)
}

@Test func distanceToBoundaryMeasuresTheNearestEdge() {
    let plot = PlotShape.rectangle(width: 50, height: 40)
    #expect(Polygon.distanceToBoundary(Point(x: 5, y: 20), polygon: plot) == 5)
    #expect(Polygon.distanceToBoundary(Point(x: 25, y: 38), polygon: plot) == 2)
    #expect(Polygon.distanceToBoundary(Point(x: 0, y: 0), polygon: []) == nil)
}

@Test func projectionClampsToTheSegment() {
    let a = Point(x: 0, y: 0), b = Point(x: 10, y: 0)
    #expect(Polygon.project(Point(x: 4, y: 7), onto: a, b) == Point(x: 4, y: 0))
    #expect(Polygon.project(Point(x: -5, y: 7), onto: a, b) == a)
    #expect(Polygon.project(Point(x: 99, y: 7), onto: a, b) == b)
    #expect(Polygon.project(Point(x: 3, y: 3), onto: a, a) == a)
}

// MARK: - Transforms

@Test func boundingBoxSwapsSidesOnAQuarterTurn() {
    let upright = Transform(x: 10, y: 10, width: 8, height: 4)
    #expect(upright.aabb == Rect(minX: 6, minY: 8, width: 8, height: 4))
    #expect(Transform(x: 10, y: 10, width: 8, height: 4, rotationDeg: 90).aabb
        == Rect(minX: 8, minY: 6, width: 4, height: 8))
    #expect(Transform(x: 10, y: 10, width: 8, height: 4, rotationDeg: 180).aabb == upright.aabb)
}

@Test func marginExpandsOnlyTheReceiver() {
    let a = Rect(minX: 0, minY: 0, width: 10, height: 10)
    let b = Rect(minX: 12, minY: 0, width: 10, height: 10)
    #expect(!a.overlaps(b))
    #expect(a.overlaps(b, margin: 3))
    #expect(!a.overlaps(b, margin: 1))
}

@Test func nearestPointLandsOnTheBoundaryForAnOutsidePoint() {
    let box = Rect(minX: 0, minY: 0, width: 10, height: 10)
    #expect(box.nearestPoint(to: Point(x: 25, y: 5)) == Point(x: 10, y: 5))
    #expect(box.nearestPoint(to: Point(x: 4, y: 6)) == Point(x: 4, y: 6))
}

/// Dragging the bottom-right corner grows the rect toward the pointer and
/// leaves the top-left where it was. The TypeScript version fails both halves,
/// landing this case at corners (-8,0)…(6,8).
@Test func resizingGrowsTowardThePointerAndPinsTheFixedCorner() {
    let fixed = Point(x: 6, y: 8)
    let pointer = Point(x: 20, y: 16)
    let resized = resizeFromCorner(
        fixedCorner: fixed,
        cornerSign: Point(x: 1, y: 1),
        rotationDeg: 0,
        pointer: pointer,
        minWidth: 1,
        minHeight: 1
    )
    #expect(resized.width == 14)
    #expect(resized.height == 8)
    #expect(resized.center == Point(x: 13, y: 12))

    let corners = resized.corners
    #expect(corners[0] == fixed)
    #expect(corners[2] == pointer)
}

@Test func resizingRespectsMinimums() {
    let resized = resizeFromCorner(
        fixedCorner: Point(x: 0, y: 0),
        cornerSign: Point(x: 1, y: 1),
        rotationDeg: 0,
        pointer: Point(x: 0.2, y: 0.2),
        minWidth: 3,
        minHeight: 2
    )
    #expect(resized.width == 3)
    #expect(resized.height == 2)
}

// MARK: - Plot shapes

/// Every corner removes the same bite. The TypeScript implementation fails
/// this for `.sw` — it takes `notchWidth × (height - notchHeight)` out of the
/// north-west instead, and its own tests never check that corner.
@Test func everyLShapeCornerRemovesTheSameArea() {
    let full = 60.0 * 45.0
    for corner in PlotCorner.allCases {
        let boundary = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: corner)
        #expect(boundary.count == 6, "\(corner)")
        #expect(Polygon.area(boundary) == full - 300, "\(corner) removed the wrong area")
    }
}

@Test func lShapeNotchesTheCornerItNames() {
    // A point just inside each named corner must fall outside the plot.
    let cases: [(PlotCorner, Point)] = [
        (.nw, Point(x: 5, y: 5)),
        (.ne, Point(x: 55, y: 5)),
        (.sw, Point(x: 5, y: 40)),
        (.se, Point(x: 55, y: 40)),
    ]
    for (corner, insideTheNotch) in cases {
        let boundary = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: corner)
        #expect(!Polygon.contains(insideTheNotch, polygon: boundary), "\(corner) did not notch its own corner")
        #expect(Polygon.contains(Point(x: 30, y: 22), polygon: boundary), "\(corner) lost its middle")
    }
}

@Test func notchIsClampedInsideThePlot() {
    let boundary = PlotShape.lShape(width: 20, height: 20, notchWidth: 500, notchHeight: 500, corner: .ne)
    #expect(Polygon.area(boundary) == 20 * 20 - 19 * 19)
}

/// Ties the geometry to the golden fixtures: the L-shaped scenario's recorded
/// plot area has to come back out of this implementation.
@Test func lShapeAreaMatchesTheFixture() throws {
    struct Fixture: Decodable {
        struct Output: Decodable {
            struct Analytics: Decodable { let totalAreaM2: Double }
            let analytics: Analytics
        }
        let output: Output
    }
    let fixture = try Fixtures.decode(Fixture.self, from: "lshape--beauty-balanced--42.json")
    let boundary = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: .ne)
    #expect(Polygon.area(boundary) == fixture.output.analytics.totalAreaM2)
}
