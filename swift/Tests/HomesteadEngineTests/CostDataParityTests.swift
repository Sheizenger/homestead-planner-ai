import Testing
import Foundation
@testable import HomesteadEngine

private struct ReferenceRegion: Decodable {
    let id: String
    let country: String
    let region: String?
    let landPricePerM2Usd: Double
    let laborIndex: Double
    let maintenanceIndex: Double
}

private struct ReferenceCostEntry: Decodable {
    let installPerM2: Double?
    let installFixed: Double?
    let annualPerM2: Double?
    let annualFixed: Double?
    let annualPerAnimal: Double?
}

private struct ReferenceSurfaceCost: Decodable {
    let install: Double
    let annual: Double
}

private struct ReferenceCostData: Decodable {
    let costRegions: [ReferenceRegion]
    let objectCostTable: [String: ReferenceCostEntry]
    let objectCategoryFallbackCost: [String: ReferenceCostEntry]
    let pathCostPerM2: [String: ReferenceSurfaceCost]
    let fenceCostPerM: [String: ReferenceSurfaceCost]
}

/// Generated from the TypeScript table rather than retyped, same discipline
/// as the object catalog and constraints — held against it field by field.
@Test func costDataMatchesTheTypeScriptTableEntryForEntry() throws {
    let reference = try Fixtures.decode(ReferenceCostData.self, from: "costData.json")

    #expect(reference.costRegions.count == CostData.costRegions.count)
    for (expected, actual) in zip(reference.costRegions, CostData.costRegions) {
        let where_ = Comment(rawValue: expected.id)
        #expect(actual.id == expected.id, where_)
        #expect(actual.country == expected.country, where_)
        #expect(actual.region == expected.region, where_)
        #expect(actual.landPricePerM2Usd == expected.landPricePerM2Usd, where_)
        #expect(actual.laborIndex == expected.laborIndex, where_)
        #expect(actual.maintenanceIndex == expected.maintenanceIndex, where_)
    }

    #expect(reference.objectCostTable.count == CostData.objectCostTable.count)
    for (typeId, expected) in reference.objectCostTable {
        let actual = CostData.objectCostTable[typeId]
        let where_ = Comment(rawValue: typeId)
        #expect(actual?.installPerM2 == expected.installPerM2, where_)
        #expect(actual?.installFixed == expected.installFixed, where_)
        #expect(actual?.annualPerM2 == expected.annualPerM2, where_)
        #expect(actual?.annualFixed == expected.annualFixed, where_)
        #expect(actual?.annualPerAnimal == expected.annualPerAnimal, where_)
    }

    #expect(reference.objectCategoryFallbackCost.count == CostData.objectCategoryFallbackCost.count)
    for (categoryRaw, expected) in reference.objectCategoryFallbackCost {
        let actual = ObjectCategory(rawValue: categoryRaw).flatMap { CostData.objectCategoryFallbackCost[$0] }
        let where_ = Comment(rawValue: categoryRaw)
        #expect(actual?.installPerM2 == expected.installPerM2, where_)
        #expect(actual?.installFixed == expected.installFixed, where_)
        #expect(actual?.annualPerM2 == expected.annualPerM2, where_)
        #expect(actual?.annualFixed == expected.annualFixed, where_)
        #expect(actual?.annualPerAnimal == expected.annualPerAnimal, where_)
    }

    for (surfaceRaw, expected) in reference.pathCostPerM2 {
        let actual = PathSurface(rawValue: surfaceRaw).flatMap { CostData.pathCostPerM2[$0] }
        #expect(actual?.install == expected.install, Comment(rawValue: surfaceRaw))
        #expect(actual?.annual == expected.annual, Comment(rawValue: surfaceRaw))
    }

    for (fenceRaw, expected) in reference.fenceCostPerM {
        let actual = FenceType(rawValue: fenceRaw).flatMap { CostData.fenceCostPerM[$0] }
        #expect(actual?.install == expected.install, Comment(rawValue: fenceRaw))
        #expect(actual?.annual == expected.annual, Comment(rawValue: fenceRaw))
    }
}
