import Testing
import Foundation
@testable import HomesteadEngine

private struct PlacementFixture: Decodable {
    struct Input: Decodable {
        let plot: Plot
        let program: [ProgramItemDTO]
    }
    struct ProgramItemDTO: Decodable {
        let typeId: String
        let width: Double
        let height: Double
        let count: Int
        let metadata: [String: JSONValue]
    }
    struct Output: Decodable {
        let objects: [PlanObject]
        let unplaced: [ProgramItemDTO]
    }
    let scenario: String
    let mode: PlanningMode
    let seed: Int
    let input: Input
    let output: Output
}

/// `placeObjects` is the single highest-risk file in the port: a shared RNG
/// stream feeds both candidate jitter and object-id suffixes, and every
/// candidate the search grid visits draws from it, rejected or not. Exact
/// equality — including generated ids — is the only proof the search grid and
/// the draw sequence actually stayed aligned with the original; a plausible
/// score or a plausible-looking layout proves nothing here.
@Test func placementMatchesEveryFixtureExactly() throws {
    let data = try Data(contentsOf: Fixtures.directory.appendingPathComponent("placement.json"))
    let fixtures = try JSONDecoder().decode([PlacementFixture].self, from: data)
    #expect(fixtures.count == 48)

    for fixture in fixtures {
        let program = fixture.input.program.map {
            Sizing.ProgramItem(typeId: $0.typeId, size: Size(width: $0.width, height: $0.height), count: $0.count, metadata: $0.metadata)
        }
        let result = Placement.placeObjects(plot: fixture.input.plot, program: program, mode: fixture.mode, seed: fixture.seed)

        let labelText = "\(fixture.scenario)--\(fixture.mode.rawValue)--\(fixture.seed)"
        #expect(result.objects.count == fixture.output.objects.count, Comment(rawValue: labelText))

        for (actual, expected) in zip(result.objects, fixture.output.objects) {
            #expect(actual == expected, Comment(rawValue: "\(labelText): \(expected.id)"))
        }

        let actualUnplaced = result.unplaced.map(\.typeId)
        let expectedUnplaced = fixture.output.unplaced.map(\.typeId)
        #expect(actualUnplaced == expectedUnplaced, Comment(rawValue: labelText))
    }
}
