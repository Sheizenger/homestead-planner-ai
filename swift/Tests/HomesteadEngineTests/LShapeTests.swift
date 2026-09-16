import Testing
import Foundation
@testable import HomesteadEngine

/// `.lshape` sat in the catalog unread since the port. These pin the shape it
/// now means, including the thing that decides whether it reads as a house —
/// that the two wings are perpendicular, not parallel.
struct LShapeTests {
    private let house = Transform(x: 20, y: -6, width: 14, height: 11)

    @Test func theTwoWingsRunAcrossEachOther() {
        let (main, cross) = LShape.wings(of: house)
        // Each is elongated along its own axis, and the axes differ. Two
        // parallel bars was the first parameterisation's failure mode.
        #expect(main.width > main.height)
        #expect(cross.height > cross.width)
        // The main range is a long bar; the cross wing is shorter but still
        // runs across it, which is what makes the roofs meet in a valley
        // rather than sitting parallel.
        #expect(main.width / main.height > 2.5)
        #expect(cross.height / cross.width > 1.15)
    }

    /// Whichever way round the box is, the bigger wing comes back first, so a
    /// caller can hang the roof pitch and the chimney off it.
    @Test func theMainWingIsTheLargerOne() {
        for box in [house, Transform(x: 0, y: 0, width: 9, height: 16)] {
            let (main, cross) = LShape.wings(of: box)
            #expect(main.width * main.height >= cross.width * cross.height)
        }
    }

    @Test func bothWingsStayInsideTheBoundingBox() {
        let (main, cross) = LShape.wings(of: house)
        for wing in [main, cross] {
            for corner in wing.corners {
                #expect(corner.x >= house.x - house.width / 2 - 1e-9)
                #expect(corner.x <= house.x + house.width / 2 + 1e-9)
                #expect(corner.y >= house.y - house.height / 2 - 1e-9)
                #expect(corner.y <= house.y + house.height / 2 + 1e-9)
            }
        }
    }

    /// The wings have to actually meet. A gap in the corner would draw as two
    /// separate buildings with a slot between them.
    @Test func theWingsMeetWithoutOverlapping() {
        let (main, cross) = LShape.wings(of: house)
        // Butted, not overlapping and not apart: a gap would draw as two
        // buildings with a slot between them, an overlap would bury one
        // wing's walls inside the other where a face sort cannot hide them.
        #expect(Polygon.clearance(main.corners, cross.corners) < 1e-9)
        #expect(abs(LShape.area(of: house) - (main.width * main.height + cross.width * cross.height)) < 1e-9)
        #expect(LShape.wingDepth(of: house) > 4)
    }

    @Test func theFootprintIsAnLNotARectangle() {
        let outline = LShape.footprint(of: house)
        #expect(outline.count == 6)
        // Six corners and a reflex one: the inside of the L. A rectangle's
        // hull is itself; this one's is strictly bigger.
        let hull = Polygon.convexHull(outline)
        #expect(hull.count == 5)
    }

    /// Every point of the L is inside the box the plot reserved for it, and
    /// the courtyard is genuinely outside the building.
    @Test func theCourtyardIsNotBuiltOn() {
        let outline = LShape.footprint(of: house)
        let yard = LShape.courtyard(of: house)
        #expect(!Polygon.contains(yard.center, polygon: outline))
        #expect(yard.width > 1 && yard.height > 1)
        // Three of the box's four corners are corners of the L; the fourth is
        // the open one, and it is the courtyard's outer corner.
        let onTheBuilding = house.corners.filter { corner in outline.contains { close($0, corner) } }
        #expect(onTheBuilding.count == 3)
        let open = house.corners.first { corner in !outline.contains { close($0, corner) } }
        #expect(open != nil)
        #expect(!Polygon.contains(open!, polygon: outline))
        // And that open corner is the far corner of the courtyard, not some
        // other corner that happens to be missing.
        #expect(distance(open!, yard.center) < distance(open!, house.center))
    }

    /// The area is the two wings less the corner they share — and it is
    /// noticeably less than the box, which is the number a cost estimate
    /// would want.
    @Test func theAreaIsTheUnionOfTheWings() {
        let area = LShape.area(of: house)
        let box = house.width * house.height
        #expect(area < box * 0.72)
        #expect(area > box * 0.5)
        #expect(abs(area - polygonArea(LShape.footprint(of: house))) < 1e-9)
    }

    /// Rotating the house rotates the L with it, rather than leaving the
    /// courtyard stuck facing one way while the walls turn.
    @Test func theShapeTurnsWithTheObject() {
        let turned = Transform(x: 20, y: -6, width: 14, height: 11, rotationDeg: 90)
        #expect(abs(LShape.area(of: turned) - LShape.area(of: house)) < 1e-9)
        let straight = LShape.footprint(of: house)
        let rotated = LShape.footprint(of: turned)
        for (a, b) in zip(straight, rotated) {
            // Each corner has moved, but the shape is congruent: same
            // distances from the centre, in the same order.
            #expect(abs(distance(a, house.center) - distance(b, turned.center)) < 1e-9)
        }
    }

    @Test func theWingDepthIsClampedToSomethingBuildable() {
        #expect(LShape.wingDepth(of: house, fraction: 0.001) == 11 * 0.25)
        #expect(LShape.wingDepth(of: house, fraction: 4) == 11 * 0.9)
        // At the upper clamp there is still an L, not a rectangle.
        #expect(LShape.area(of: house, fraction: 4) < house.width * house.height)
    }

    // MARK: -

    private func close(_ a: Point, _ b: Point) -> Bool { distance(a, b) < 1e-9 }

    private func distance(_ a: Point, _ b: Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private func polygonArea(_ points: [Point]) -> Double {
        var total = 0.0
        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            total += a.x * b.y - b.x * a.y
        }
        return abs(total) / 2
    }
}
