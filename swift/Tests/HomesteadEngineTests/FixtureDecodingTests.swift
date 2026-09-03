import Testing
import Foundation
@testable import HomesteadEngine

struct FixtureIndex: Decodable {
    struct Entry: Decodable {
        let file: String
        let scenario: String
        let mode: PlanningMode
        let seed: Int
    }
    let fixtures: [Entry]
}

struct GoldenFixture: Decodable {
    struct Input: Decodable {
        let plot: Plot
        let brief: Brief
        let mode: PlanningMode
        let seed: Int
    }
    let covers: String
    let input: Input
    let output: Layout
}

extension Fixtures {
    static func index() throws -> [FixtureIndex.Entry] {
        try decode(FixtureIndex.self, from: "index.json").fixtures
    }

    static func golden(_ file: String) throws -> GoldenFixture {
        try decode(GoldenFixture.self, from: file)
    }
}

/// The domain model has to round-trip every fixture before any planner logic
/// is worth writing: a decoding failure here is a mismatch between the Swift
/// types and the shape the TypeScript engine actually emits, and it would
/// otherwise surface as an unrelated-looking comparison failure later.
@Test func everyFixtureDecodesIntoTheDomainModel() throws {
    let index = try Fixtures.index()
    #expect(index.count == 48)

    for entry in index {
        let fixture = try Fixtures.golden(entry.file)
        #expect(fixture.output.mode == entry.mode, Comment(rawValue: entry.file))
        #expect(fixture.output.seed == entry.seed, Comment(rawValue: entry.file))
        #expect(fixture.input.plot.boundary.count >= 4, Comment(rawValue: entry.file))
        #expect(!fixture.output.objects.isEmpty, Comment(rawValue: entry.file))
    }
}

/// Area accounting has to hold in the reference data itself, or the port has
/// nothing trustworthy to reproduce.
@Test func fixtureAnalyticsAreSelfConsistent() throws {
    for entry in try Fixtures.index() {
        let fixture = try Fixtures.golden(entry.file)
        let analytics = fixture.output.analytics

        let plotArea = Polygon.area(fixture.input.plot.boundary)
        #expect(abs(analytics.totalAreaM2 - plotArea) < 1e-6, Comment(rawValue: entry.file))
        #expect(
            abs(analytics.allocatedAreaM2 + analytics.unallocatedAreaM2 - analytics.totalAreaM2) < 1e-6,
            Comment(rawValue: entry.file)
        )

        let summed = analytics.byCategory.reduce(0) { $0 + $1.areaM2 }
        #expect(abs(summed - analytics.allocatedAreaM2) < 1e-6, Comment(rawValue: entry.file))
    }
}

/// Every warning and utility node points at objects that exist, and every
/// object's layer agrees with its category. Cheap invariants, but they pin
/// down the relationships the port has to preserve.
@Test func fixtureReferencesResolve() throws {
    for entry in try Fixtures.index() {
        let fixture = try Fixtures.golden(entry.file)
        let objectIds = Set(fixture.output.objects.map(\.id))
        let nodeIds = Set(fixture.output.utilityNodes.map(\.id))

        for warning in fixture.output.warnings {
            for id in warning.objectIds {
                #expect(objectIds.contains(id), Comment(rawValue: "\(entry.file): warning \(warning.id) cites a missing object"))
            }
        }
        for node in fixture.output.utilityNodes {
            #expect(objectIds.contains(node.objectId), Comment(rawValue: "\(entry.file): node \(node.id) cites a missing object"))
            for connection in node.connections {
                #expect(nodeIds.contains(connection), Comment(rawValue: "\(entry.file): node \(node.id) links to a missing node"))
            }
        }
        for object in fixture.output.objects {
            #expect(object.layerId == object.category, Comment(rawValue: "\(entry.file): \(object.id) layer disagrees with category"))
        }
    }
}
