import Testing
@testable import HomesteadEngine

/// `synthesizePaths`/`synthesizeFences` are pure functions of the objects
/// `generate.ts` already placed and the plot — generate.ts calls them with
/// exactly the `objects` array that ends up in each fixture's
/// `output.objects`, so the 48 golden fixtures verify this file directly.
/// No separate isolated fixture needed, unlike Placement.
@Test func pathsAndFencesMatchEveryGoldenFixture() throws {
    for entry in try Fixtures.index() {
        let fixture = try Fixtures.golden(entry.file)
        let comment = Comment(rawValue: entry.file)

        let paths = PathsAndFences.synthesizePaths(objects: fixture.output.objects, plot: fixture.input.plot)
        #expect(paths == fixture.output.paths, comment)

        let fences = PathsAndFences.synthesizeFences(objects: fixture.output.objects, plot: fixture.input.plot)
        #expect(fences == fixture.output.fences, comment)
    }
}

/// Expected point captured by running the real `findGatePoint` in Node — the
/// south edge (highest average y) is water and gets skipped, but the next
/// tie between east and west (both mid-y 20) resolves to whichever the
/// boundary lists first, not to the lowest-y north edge; guessing the answer
/// from the doc comment alone would have gotten this wrong.
@Test func gateSkipsAWaterfrontEdgeEvenWhenItWouldOtherwiseWin() {
    let boundary = PlotShape.rectangle(width: 50, height: 40)
    let waterfront = Rect(minX: 0, minY: 30, width: 50, height: 10)
    let gate = PathsAndFences.findGatePoint(boundary: boundary, houseCenter: Point(x: 25, y: 15), waterfrontBounds: waterfront)
    #expect(gate == Point(x: 50, y: 15))
}
