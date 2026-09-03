import Testing
import Foundation
@testable import HomesteadEngine

/// The TypeScript entry shape, decoded straight from the emitted catalog.
private struct ReferenceEntry: Decodable {
    let id: String
    let label: String
    let category: ObjectCategory
    let shape: ObjectLibrary.Shape
    let defaultWidth: Double
    let defaultHeight: Double
    let minWidth: Double
    let minHeight: Double
    let sunNeed: ObjectLibrary.SunNeed
    let noiseLevel: ObjectLibrary.NoiseLevel
    let odorLevel: ObjectLibrary.OdorLevel
    let needsAccess: Bool
    let requiresFence: Bool
    let description: String
}

/// Thirty entries of dimensions and flags is exactly the kind of table where a
/// transcription slip hides: a paddock two metres short still looks plausible
/// on screen and only shows up as a containment warning nobody expects. Held
/// against the TypeScript catalog field by field.
@Test func catalogMatchesTheTypeScriptTableEntryForEntry() throws {
    let reference = try Fixtures.decode([String: ReferenceEntry].self, from: "objectLibrary.json")

    #expect(reference.count == ObjectLibrary.all.count)
    #expect(Set(reference.keys) == Set(ObjectLibrary.all.map(\.id)))

    for (id, expected) in reference {
        guard let entry = ObjectLibrary[id] else {
            Issue.record("catalog is missing \(id)")
            continue
        }
        let where_ = Comment(rawValue: id)
        #expect(entry.label == expected.label, where_)
        #expect(entry.category == expected.category, where_)
        #expect(entry.shape == expected.shape, where_)
        #expect(entry.defaultSize.width == expected.defaultWidth, where_)
        #expect(entry.defaultSize.height == expected.defaultHeight, where_)
        #expect(entry.minimumSize.width == expected.minWidth, where_)
        #expect(entry.minimumSize.height == expected.minHeight, where_)
        #expect(entry.sunNeed == expected.sunNeed, where_)
        #expect(entry.noiseLevel == expected.noiseLevel, where_)
        #expect(entry.odorLevel == expected.odorLevel, where_)
        #expect(entry.needsAccess == expected.needsAccess, where_)
        #expect(entry.requiresFence == expected.requiresFence, where_)
        #expect(entry.description == expected.description, where_)
    }
}

/// Ids are the join key between the catalog, placed objects and the fixtures,
/// so a duplicate would silently shadow an entry.
@Test func catalogIDsAreUnique() {
    #expect(Set(ObjectLibrary.all.map(\.id)).count == ObjectLibrary.all.count)
}

@Test func everyPlacedObjectInEveryFixtureNamesAKnownType() throws {
    for entry in try Fixtures.index() {
        let fixture = try Fixtures.golden(entry.file)
        for object in fixture.output.objects {
            #expect(
                ObjectLibrary[object.typeId] != nil,
                Comment(rawValue: "\(entry.file): \(object.typeId) is not in the catalog")
            )
        }
    }
}

@Test func houseTypesResolve() {
    for id in ObjectLibrary.houseTypeIDs {
        #expect(ObjectLibrary[id]?.category == .residential, Comment(rawValue: id))
    }
}
