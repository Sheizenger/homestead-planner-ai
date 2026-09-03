import Foundation

/// Ported from `src/engine/analytics.ts`.
public enum Analytics {
    private static let foodCategories: Set<ZoneCategory> = [.foodAnnual, .foodPerennial, .greenhouse]

    private static let annualMaintenanceWeight: [ZoneCategory: Double] = [
        .foodAnnual: 3, .animal: 3.5, .greenhouse: 2.5, .foodPerennial: 1,
        .residential: 0.5, .energy: 1, .water: 0.5, .utility: 1,
        .storage: 0.5, .leisure: 0.5, .access: 0.2, .futureExpansion: 0,
    ]

    public static func compute(objects: [PlanObject], zones: [Zone], plot: Plot) -> AnalyticsSnapshot {
        let totalAreaM2 = Polygon.area(plot.boundary)

        // A plain JavaScript Map accumulates by category in first-insertion
        // order, and both sums below iterate its values in that same order —
        // floating-point addition isn't associative, so which category is
        // seen first (objects, then zones, in their given array order)
        // changes the summed bit pattern, not just cosmetically.
        var categoryOrder: [ZoneCategory] = []
        var byCategoryMap: [ZoneCategory: Double] = [:]
        func add(_ category: ZoneCategory, _ area: Double) {
            if byCategoryMap[category] == nil { categoryOrder.append(category) }
            byCategoryMap[category, default: 0] += area
        }

        for object in objects {
            guard let category = ZoneCategory(rawValue: object.category.rawValue) else { continue }
            if object.metadata["roofMounted"]?.boolValue == true { continue } // shares the house's footprint
            add(category, object.transform.width * object.transform.height)
        }
        for zone in zones {
            add(zone.category, Polygon.area(zone.boundary))
        }

        let allocatedAreaM2 = categoryOrder.reduce(0.0) { $0 + byCategoryMap[$1]! }
        let unallocatedAreaM2 = max(0, totalAreaM2 - allocatedAreaM2)

        let byCategory: [CategoryArea] = ZONE_CATEGORY_ORDER.compactMap { category in
            guard let areaM2 = byCategoryMap[category] else { return nil }
            let percent = totalAreaM2 > 0 ? (areaM2 / totalAreaM2) * 100 : 0
            return CategoryArea(category: category, areaM2: areaM2, percent: percent)
        }

        let foodArea = foodCategories.reduce(0.0) { $0 + (byCategoryMap[$1] ?? 0) }
        let estimatedFoodProductionScore = totalAreaM2 > 0 ? min(100, (foodArea / totalAreaM2) * 220) : 0

        let maintenanceRaw = categoryOrder.reduce(0.0) { $0 + byCategoryMap[$1]! * (annualMaintenanceWeight[$1] ?? 1) }
        let maintenanceComplexityScore = totalAreaM2 > 0 ? min(100, (maintenanceRaw / totalAreaM2) * 12) : 0

        return AnalyticsSnapshot(
            totalAreaM2: totalAreaM2,
            allocatedAreaM2: allocatedAreaM2,
            unallocatedAreaM2: unallocatedAreaM2,
            byCategory: byCategory,
            estimatedFoodProductionScore: estimatedFoodProductionScore,
            maintenanceComplexityScore: maintenanceComplexityScore
        )
    }
}

/// The order categories are ever reported in — a separate concern from the
/// insertion order the sums above depend on. Ported from
/// `src/domain/categories.ts`.
public let ZONE_CATEGORY_ORDER: [ZoneCategory] = [
    .residential, .access, .foodAnnual, .foodPerennial, .greenhouse, .animal,
    .utility, .water, .energy, .storage, .leisure, .futureExpansion,
]
