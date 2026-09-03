import Testing
@testable import HomesteadEngine

/// `computeUtilityNodes` is a pure function of `generate.ts`'s placed
/// objects, called with exactly the array that ends up in each fixture's
/// `output.objects` — so the 48 golden fixtures verify this file directly.
@Test func utilityNodesMatchEveryGoldenFixture() throws {
    for entry in try Fixtures.index() {
        let fixture = try Fixtures.golden(entry.file)
        let nodes = UtilityConnections.computeNodes(fixture.output.objects)
        #expect(nodes == fixture.output.utilityNodes, Comment(rawValue: entry.file))
    }
}
