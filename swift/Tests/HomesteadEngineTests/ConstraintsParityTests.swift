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

/// `.generic` overrides and adds nothing (see `RegulatoryRegion`'s doc
/// comment) — it must reproduce `all`/`boundarySetbacks` exactly, since
/// those are what the golden fixtures are pinned against. This is the
/// regression guard for the region-aware accessors introduced alongside
/// per-region placement/warnings.
@Test func genericRegionReproducesTheBaselineExactly() {
    #expect(Constraints.all(for: .generic) == Constraints.all)
    #expect(Constraints.boundarySetbacks(for: .generic) == Constraints.boundarySetbacks)
}

/// SanPiN/RF replaces the generic flat fire-separation guidance with its
/// own (a different id, a stricter distance) rather than adding a second,
/// redundant warning alongside it — proving the override half of the
/// contract, not just the additive half `.generic` exercises above.
@Test func sanPiNOverridesTheGenericFireSeparationRule() {
    let sanPiN = Constraints.all(for: .ruSanPiN)
    #expect(!sanPiN.contains { $0.id == "fire-house-outbuilding-separation" })
    let override = sanPiN.first { $0.id == "ru-sanpin-fire-house-outbuilding-separation" }
    #expect(override?.minDistance == 15)
    // Every other baseline constraint is untouched.
    #expect(sanPiN.count == Constraints.all.count)
}

/// Germany and Spain both override the generic house boundary setback
/// (same relationship, a different legal basis) rather than duplicate it.
@Test func euRegionsOverrideTheGenericHouseSetback() {
    for (region, id) in [(RegulatoryRegion.deGeneric, "de-setback-house"), (RegulatoryRegion.esGeneric, "es-setback-house")] {
        let setbacks = Constraints.boundarySetbacks(for: region)
        #expect(!setbacks.contains { $0.id == "setback-house" }, Comment(rawValue: region.rawValue))
        #expect(setbacks.contains { $0.id == id }, Comment(rawValue: region.rawValue))
        #expect(setbacks.count == Constraints.boundarySetbacks.count, Comment(rawValue: region.rawValue))
    }
}
