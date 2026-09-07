import Foundation

/// Ported from `src/engine/costs.ts`. A real bill-of-quantities view turned
/// straight into money — as opposed to `Materials`, which exposes the raw
/// quantities a contractor would actually order against.
public struct CostRow: Equatable, Codable, Sendable {
    public let label: String
    public let category: ZoneCategory?
    public let special: SpecialRow?
    public let installUsd: Double
    public let annualUsd: Double
}

public enum SpecialRow: String, Codable, Sendable {
    case paths, fencing
}

public struct CostEstimate: Equatable, Codable, Sendable {
    public let region: CostRegion
    public let landAreaM2: Double
    public let landCostUsd: Double
    public let rows: [CostRow]
    public let constructionTotalUsd: Double
    public let annualMaintenanceTotalUsd: Double
    public let totalUpfrontUsd: Double
}

public enum Costs {
    private static func polylineLength(_ points: [Point]) -> Double {
        var length = 0.0
        for i in 0..<max(0, points.count - 1) { length += distance(points[i], points[i + 1]) }
        return length
    }

    public static func estimate(objects: [PlanObject], paths: [PathEntity], fences: [Fence], totalAreaM2: Double, region: CostRegion) -> CostEstimate {
        let landAreaM2 = totalAreaM2
        let landCostUsd = landAreaM2 * region.landPricePerM2Usd

        // A JavaScript Map accumulates in first-insertion order; the two
        // running sums below (construction/annual totals) read from this in
        // ZONE_CATEGORY_ORDER, not insertion order, so — unlike Analytics —
        // no tie to the object array's order survives into the output here.
        var byCategory: [ZoneCategory: (install: Double, annual: Double)] = [:]
        func add(_ category: ZoneCategory, install: Double, annual: Double) {
            var entry = byCategory[category] ?? (0, 0)
            entry.install += install
            entry.annual += annual
            byCategory[category] = entry
        }

        for object in objects {
            if object.locked { continue } // as-built structures aren't a new expense
            guard let category = object.category.zoneCategory else { continue }
            guard let entry = CostData.objectCostTable[object.typeId] ?? CostData.objectCategoryFallbackCost[object.category] else { continue }
            let areaM2 = object.transform.width * object.transform.height
            let animalCount = object.metadata["animalCount"]?.doubleValue ?? 0
            let install = ((entry.installPerM2 ?? 0) * areaM2 + (entry.installFixed ?? 0)) * region.laborIndex
            let annual = ((entry.annualPerM2 ?? 0) * areaM2 + (entry.annualFixed ?? 0) + (entry.annualPerAnimal ?? 0) * animalCount) * region.maintenanceIndex
            add(category, install: install, annual: annual)
        }

        var pathInstall = 0.0, pathAnnual = 0.0
        for path in paths {
            let cost = CostData.pathCostPerM2[path.surfaceType] ?? CostData.pathCostPerM2[.gravel]!
            let areaM2 = polylineLength(path.points) * path.widthM
            pathInstall += cost.install * areaM2 * region.laborIndex
            pathAnnual += cost.annual * areaM2 * region.maintenanceIndex
        }

        var fenceInstall = 0.0, fenceAnnual = 0.0
        for fence in fences {
            let cost = CostData.fenceCostPerM[fence.fenceType] ?? CostData.fenceCostPerM[.garden]!
            guard let first = fence.points.first else { continue }
            let lengthM = polylineLength(fence.points + [first])
            fenceInstall += cost.install * lengthM * region.laborIndex
            fenceAnnual += cost.annual * lengthM * region.maintenanceIndex
        }

        var rows: [CostRow] = ZONE_CATEGORY_ORDER.compactMap { category -> CostRow? in
            guard let entry = byCategory[category] else { return nil }
            return CostRow(label: CategoryStyles.label[category]!, category: category, special: nil, installUsd: entry.install, annualUsd: entry.annual)
        }
        if pathInstall > 0 || pathAnnual > 0 {
            rows.append(CostRow(label: "Paths", category: nil, special: .paths, installUsd: pathInstall, annualUsd: pathAnnual))
        }
        if fenceInstall > 0 || fenceAnnual > 0 {
            rows.append(CostRow(label: "Fencing", category: nil, special: .fencing, installUsd: fenceInstall, annualUsd: fenceAnnual))
        }

        let constructionTotalUsd = rows.reduce(0.0) { $0 + $1.installUsd }
        let annualMaintenanceTotalUsd = rows.reduce(0.0) { $0 + $1.annualUsd }

        return CostEstimate(
            region: region,
            landAreaM2: landAreaM2,
            landCostUsd: landCostUsd,
            rows: rows,
            constructionTotalUsd: constructionTotalUsd,
            annualMaintenanceTotalUsd: annualMaintenanceTotalUsd,
            totalUpfrontUsd: landCostUsd + constructionTotalUsd
        )
    }
}

/// The category display label `Costs` borrows from
/// `src/domain/categories.ts`'s `CATEGORY_STYLES[category].label` — the rest
/// of that table (colours) is a view concern with no engine role.
enum CategoryStyles {
    static let label: [ZoneCategory: String] = [
        .residential: "Residential", .access: "Access & Paths", .foodAnnual: "Annual Crops",
        .foodPerennial: "Orchard & Berries", .greenhouse: "Greenhouse", .animal: "Animals",
        .utility: "Utilities", .water: "Water", .energy: "Energy", .storage: "Storage",
        .leisure: "Leisure", .futureExpansion: "Future Expansion",
    ]
}
