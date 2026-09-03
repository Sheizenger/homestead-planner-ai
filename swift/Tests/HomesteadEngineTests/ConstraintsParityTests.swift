import Testing
import Foundation
@testable import HomesteadEngine

private struct ReferenceConstraint: Decodable {
    let id: String
    let kind: ConstraintKind
    let subjectTypes: [String]
    let relatedTypes: [String]
    let minDistance: Double?
    let maxDistance: Double?
    let hard: Bool
    let severity: WarningSeverity
    let message: String
}

private struct ReferenceSetback: Decodable {
    let id: String
    let appliesTo: [String]
    let minDistanceM: Double
    let severity: WarningSeverity
    let message: String
}

private struct ReferenceData: Decodable {
    let constraints: [ReferenceConstraint]
    let boundarySetbacks: [ReferenceSetback]
}

/// 23 constraints and 6 setbacks generated from the TypeScript source rather
/// than retyped, held against it field by field — the same discipline as the
/// object catalog, and for the same reason: a wrong distance here changes
/// what the placement search accepts without looking wrong on screen.
@Test func constraintsMatchTheTypeScriptTableEntryForEntry() throws {
    let reference = try Fixtures.decode(ReferenceData.self, from: "constraints.json")

    #expect(reference.constraints.count == Constraints.all.count)
    for (expected, actual) in zip(reference.constraints, Constraints.all) {
        let where_ = Comment(rawValue: expected.id)
        #expect(actual.id == expected.id, where_)
        #expect(actual.kind == expected.kind, where_)
        #expect(actual.subjectTypes == expected.subjectTypes, where_)
        #expect(actual.relatedTypes == expected.relatedTypes, where_)
        #expect(actual.minDistance == expected.minDistance, where_)
        #expect(actual.maxDistance == expected.maxDistance, where_)
        #expect(actual.hard == expected.hard, where_)
        #expect(actual.severity == expected.severity, where_)
        #expect(actual.message == expected.message, where_)
    }

    #expect(reference.boundarySetbacks.count == Constraints.boundarySetbacks.count)
    for (expected, actual) in zip(reference.boundarySetbacks, Constraints.boundarySetbacks) {
        let where_ = Comment(rawValue: expected.id)
        #expect(actual.id == expected.id, where_)
        #expect(actual.appliesTo == expected.appliesTo, where_)
        #expect(actual.minDistanceM == expected.minDistanceM, where_)
        #expect(actual.severity == expected.severity, where_)
        #expect(actual.message == expected.message, where_)
    }
}

@Test func matchesChecksIdOrCategory() {
    let well = ObjectLibrary["well"]!
    #expect(Constraints.matches(well, ["well"]))
    #expect(Constraints.matches(well, ["water"]))
    #expect(!Constraints.matches(well, ["septic"]))
}
