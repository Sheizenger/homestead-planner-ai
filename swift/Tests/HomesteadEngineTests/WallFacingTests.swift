import Testing
@testable import HomesteadEngine

/// Where a door goes. A garage door has to face the gate: a car arrives from
/// the road and leaves toward it, so any other choice puts the door on a blank
/// elevation — which is what "a garage with a door facing a solid fence"
/// meant.
struct WallFacingTests {
    private let box = Transform(x: 10, y: 10, width: 6, height: 4)

    /// `corners` is TL, TR, BR, BL in the object's own frame, and `+y` is
    /// south, so these are the four walls by compass point.
    private var north: (Point, Point) { (Point(x: 7, y: 8), Point(x: 13, y: 8)) }
    private var south: (Point, Point) { (Point(x: 7, y: 12), Point(x: 13, y: 12)) }

    private func isSameWall(_ a: (Point, Point), _ b: (Point, Point)) -> Bool {
        (a.0 == b.0 && a.1 == b.1) || (a.0 == b.1 && a.1 == b.0)
    }

    @Test func theWallChosenIsTheOneFacingTheTarget() {
        #expect(isSameWall(box.wall(facing: Point(x: 10, y: 40)), south))
        #expect(isSameWall(box.wall(facing: Point(x: 10, y: -20)), north))

        let east = box.wall(facing: Point(x: 60, y: 10))
        #expect(east.0.x == 13 && east.1.x == 13)
        let west = box.wall(facing: Point(x: -40, y: 10))
        #expect(west.0.x == 7 && west.1.x == 7)
    }

    /// The case that matters: a target diagonally off one corner still has to
    /// resolve to one wall, and to the nearer-facing of the two.
    @Test func aDiagonalTargetPicksTheWallItFacesMost() {
        // Mostly east, a little south.
        let wall = box.wall(facing: Point(x: 60, y: 16))
        #expect(wall.0.x == 13 && wall.1.x == 13)
        // Mostly south, a little east.
        let other = box.wall(facing: Point(x: 16, y: 60))
        #expect(isSameWall(other, south))
    }

    /// A target at the centre has no direction; the south wall is the
    /// engine's own "front" and is what the caller falls back to.
    @Test func aTargetOnTheCentreFallsBackToTheFront() {
        #expect(isSameWall(box.wall(facing: box.center), south))
    }

    /// End to end: the garage's door wall faces the gate the driveway comes
    /// from, on every seed.
    @Test func theGarageFacesTheGate() {
        var inputs = StructuredInputs()
        inputs.householdSize = 4
        inputs.infrastructure = ["garage"]
        let brief = Brief(structuredInputs: inputs)

        var checked = 0
        for seed in 1...6 {
            let plot = Plot(boundary: PlotShape.rectangle(width: 80, height: 60))
            let layout = Generate.variant(plot: plot, brief: brief, mode: .beautyBalanced, seed: seed)
            guard let garage = layout.objects.first(where: { $0.typeId == "garage" }),
                  let house = layout.objects.first(where: { ObjectLibrary.houseTypeIDs.contains($0.typeId) })
            else { continue }
            checked += 1

            let gate = PathsAndFences.findGatePoint(
                boundary: plot.boundary,
                houseCenter: house.transform.center,
                waterfrontBounds: nil
            )
            let wall = garage.transform.wall(facing: gate)
            let middle = Point(x: (wall.0.x + wall.1.x) / 2, y: (wall.0.y + wall.1.y) / 2)

            // The door wall's midpoint is nearer the gate than the garage's
            // own centre is — which is what "facing it" means.
            #expect(distance(middle, gate) < distance(garage.transform.center, gate), Comment(rawValue: "seed \(seed)"))
        }
        #expect(checked >= 5)
    }
}
