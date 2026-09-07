import Foundation

/// Ported from `src/domain/costData.ts`. Rough planning figures throughout —
/// not appraisals or contractor quotes — generated from the TypeScript table
/// rather than retyped, and held against it field by field by
/// `CostDataParityTests`, the same discipline as the object catalog and
/// constraints.
public enum CurrencyCode: String, CaseIterable, Codable, Sendable {
    case usd = "USD"
    case eur = "EUR"
    case rub = "RUB"
}

public enum Currency {
    public static let symbols: [CurrencyCode: String] = [.usd: "$", .eur: "€", .rub: "₽"]

    /// Static, approximate — not a live feed. Good enough for
    /// order-of-magnitude planning; refresh periodically if used for
    /// anything more serious.
    public static let usdExchangeRates: [CurrencyCode: Double] = [.usd: 1, .eur: 0.92, .rub: 82]

    public static func convert(fromUsd amountUsd: Double, to currency: CurrencyCode) -> Double {
        amountUsd * (usdExchangeRates[currency] ?? 1)
    }
}

public struct CostRegion: Equatable, Codable, Sendable {
    public let id: String
    public let country: String
    /// State / federal subject / etc.
    public let region: String?
    public let landPricePerM2Usd: Double
    /// Construction/installation cost multiplier, US-national = 1.0.
    public let laborIndex: Double
    /// Ongoing upkeep cost multiplier.
    public let maintenanceIndex: Double

    public init(id: String, country: String, region: String?, landPricePerM2Usd: Double, laborIndex: Double, maintenanceIndex: Double) {
        self.id = id
        self.country = country
        self.region = region
        self.landPricePerM2Usd = landPricePerM2Usd
        self.laborIndex = laborIndex
        self.maintenanceIndex = maintenanceIndex
    }

    public var label: String {
        if let region, region != "National average" { return "\(country) — \(region)" }
        return country
    }
}

public struct ObjectCostEntry: Equatable, Sendable {
    public let installPerM2: Double?
    public let installFixed: Double?
    public let annualPerM2: Double?
    public let annualFixed: Double?
    /// Uses `metadata["animalCount"]` when present.
    public let annualPerAnimal: Double?

    public init(installPerM2: Double? = nil, installFixed: Double? = nil, annualPerM2: Double? = nil, annualFixed: Double? = nil, annualPerAnimal: Double? = nil) {
        self.installPerM2 = installPerM2
        self.installFixed = installFixed
        self.annualPerM2 = annualPerM2
        self.annualFixed = annualFixed
        self.annualPerAnimal = annualPerAnimal
    }
}

public enum CostData {
    /// Land prices and labor indices are rough 2025-market-report
    /// approximations converted to a common USD/m² baseline for comparison —
    /// not appraisals. "Custom / other location" is meant to be overridden
    /// with local knowledge.
    public static let costRegions: [CostRegion] = [
        CostRegion(id: "custom", country: "Custom / other location", region: nil, landPricePerM2Usd: 5, laborIndex: 1, maintenanceIndex: 1),
        CostRegion(id: "us-national", country: "United States", region: "National average", landPricePerM2Usd: 3, laborIndex: 1, maintenanceIndex: 1),
        CostRegion(id: "us-california", country: "United States", region: "California", landPricePerM2Usd: 35, laborIndex: 1.3, maintenanceIndex: 1.2),
        CostRegion(id: "us-texas", country: "United States", region: "Texas", landPricePerM2Usd: 2.5, laborIndex: 0.85, maintenanceIndex: 0.9),
        CostRegion(id: "de-national", country: "Germany", region: "National average", landPricePerM2Usd: 239, laborIndex: 1.2, maintenanceIndex: 1.1),
        CostRegion(id: "de-bavaria", country: "Germany", region: "Bavaria", landPricePerM2Usd: 429, laborIndex: 1.35, maintenanceIndex: 1.2),
        CostRegion(id: "de-saxony-anhalt", country: "Germany", region: "Saxony-Anhalt", landPricePerM2Usd: 87, laborIndex: 0.95, maintenanceIndex: 0.9),
        CostRegion(id: "ru-national", country: "Russia", region: "Rural average", landPricePerM2Usd: 1.8, laborIndex: 0.4, maintenanceIndex: 0.4),
        CostRegion(id: "ru-moscow-region", country: "Russia", region: "Moscow Region", landPricePerM2Usd: 49, laborIndex: 0.5, maintenanceIndex: 0.45),
        CostRegion(id: "ua-national", country: "Ukraine", region: "National average", landPricePerM2Usd: 0.6, laborIndex: 0.25, maintenanceIndex: 0.3),
        CostRegion(id: "kz-national", country: "Kazakhstan", region: "National average", landPricePerM2Usd: 0.5, laborIndex: 0.3, maintenanceIndex: 0.3),
        CostRegion(id: "uk-national", country: "United Kingdom", region: "National average", landPricePerM2Usd: 20, laborIndex: 1.3, maintenanceIndex: 1.2),
        CostRegion(id: "fr-national", country: "France", region: "National average", landPricePerM2Usd: 15, laborIndex: 1.15, maintenanceIndex: 1.1),
        CostRegion(id: "es-national", country: "Spain", region: "National average", landPricePerM2Usd: 8, laborIndex: 0.9, maintenanceIndex: 0.9),
        CostRegion(id: "ca-national", country: "Canada", region: "National average", landPricePerM2Usd: 6, laborIndex: 1.1, maintenanceIndex: 1.05),
        CostRegion(id: "pl-national", country: "Poland", region: "National average", landPricePerM2Usd: 4, laborIndex: 0.55, maintenanceIndex: 0.5),
    ]

    /// US-national baseline (laborIndex 1.0) construction/installation and
    /// annual upkeep costs in USD, per object-library type id. Scaled per
    /// region by laborIndex/maintenanceIndex in `Costs`. Rough planning
    /// figures, not contractor quotes.
    public static let objectCostTable: [String: ObjectCostEntry] = [
        "house": ObjectCostEntry(installPerM2: 2000, installFixed: nil, annualPerM2: 15, annualFixed: nil, annualPerAnimal: nil),
        "house-l": ObjectCostEntry(installPerM2: 2050, installFixed: nil, annualPerM2: 15, annualFixed: nil, annualPerAnimal: nil),
        "garage": ObjectCostEntry(installPerM2: 500, installFixed: nil, annualPerM2: 8, annualFixed: nil, annualPerAnimal: nil),
        "shed": ObjectCostEntry(installPerM2: 250, installFixed: nil, annualPerM2: 4, annualFixed: nil, annualPerAnimal: nil),
        "barn": ObjectCostEntry(installPerM2: 350, installFixed: nil, annualPerM2: 6, annualFixed: nil, annualPerAnimal: nil),
        "cellar": ObjectCostEntry(installPerM2: 400, installFixed: nil, annualPerM2: 3, annualFixed: nil, annualPerAnimal: nil),
        "woodshed": ObjectCostEntry(installPerM2: 200, installFixed: nil, annualPerM2: 3, annualFixed: nil, annualPerAnimal: nil),
        "patio": ObjectCostEntry(installPerM2: 120, installFixed: nil, annualPerM2: 2, annualFixed: nil, annualPerAnimal: nil),
        "greenhouse": ObjectCostEntry(installPerM2: 180, installFixed: nil, annualPerM2: 12, annualFixed: nil, annualPerAnimal: nil),
        "hydroponic-tower": ObjectCostEntry(installPerM2: 350, installFixed: nil, annualPerM2: 40, annualFixed: nil, annualPerAnimal: nil),
        "raised-beds": ObjectCostEntry(installPerM2: 60, installFixed: nil, annualPerM2: 8, annualFixed: nil, annualPerAnimal: nil),
        "vegetable-area": ObjectCostEntry(installPerM2: 8, installFixed: nil, annualPerM2: 6, annualFixed: nil, annualPerAnimal: nil),
        "potato-area": ObjectCostEntry(installPerM2: 5, installFixed: nil, annualPerM2: 4, annualFixed: nil, annualPerAnimal: nil),
        "grain-field": ObjectCostEntry(installPerM2: 4, installFixed: nil, annualPerM2: 3, annualFixed: nil, annualPerAnimal: nil),
        "orchard-trees": ObjectCostEntry(installPerM2: 12, installFixed: nil, annualPerM2: 3, annualFixed: nil, annualPerAnimal: nil),
        "berry-rows": ObjectCostEntry(installPerM2: 15, installFixed: nil, annualPerM2: 5, annualFixed: nil, annualPerAnimal: nil),
        "vineyard": ObjectCostEntry(installPerM2: 20, installFixed: nil, annualPerM2: 6, annualFixed: nil, annualPerAnimal: nil),
        "goat-shelter": ObjectCostEntry(installPerM2: 300, installFixed: nil, annualPerM2: 5, annualFixed: nil, annualPerAnimal: nil),
        "goat-paddock": ObjectCostEntry(installPerM2: 6, installFixed: nil, annualPerM2: 2, annualFixed: nil, annualPerAnimal: 250),
        "poultry-coop": ObjectCostEntry(installPerM2: 250, installFixed: nil, annualPerM2: 5, annualFixed: nil, annualPerAnimal: 25),
        "compost": ObjectCostEntry(installPerM2: nil, installFixed: 150, annualPerM2: nil, annualFixed: 20, annualPerAnimal: nil),
        "water-tank": ObjectCostEntry(installPerM2: nil, installFixed: 1500, annualPerM2: nil, annualFixed: 40, annualPerAnimal: nil),
        "well": ObjectCostEntry(installPerM2: nil, installFixed: 4500, annualPerM2: nil, annualFixed: 100, annualPerAnimal: nil),
        "pump": ObjectCostEntry(installPerM2: nil, installFixed: 900, annualPerM2: nil, annualFixed: 60, annualPerAnimal: nil),
        "septic": ObjectCostEntry(installPerM2: nil, installFixed: 6000, annualPerM2: nil, annualFixed: 150, annualPerAnimal: nil),
        "solar-array": ObjectCostEntry(installPerM2: 280, installFixed: nil, annualPerM2: nil, annualFixed: 100, annualPerAnimal: nil),
        "battery-room": ObjectCostEntry(installPerM2: nil, installFixed: 5000, annualPerM2: nil, annualFixed: 80, annualPerAnimal: nil),
        "inverter-room": ObjectCostEntry(installPerM2: nil, installFixed: 1800, annualPerM2: nil, annualFixed: 40, annualPerAnimal: nil),
        "generator": ObjectCostEntry(installPerM2: nil, installFixed: 1200, annualPerM2: nil, annualFixed: 150, annualPerAnimal: nil),
        "pool": ObjectCostEntry(installPerM2: 900, installFixed: nil, annualPerM2: 15, annualFixed: 600, annualPerAnimal: nil),
        "gazebo": ObjectCostEntry(installPerM2: 250, installFixed: nil, annualPerM2: 3, annualFixed: nil, annualPerAnimal: nil),
        "apiary": ObjectCostEntry(installPerM2: nil, installFixed: 800, annualPerM2: nil, annualFixed: 150, annualPerAnimal: nil),
        "banya": ObjectCostEntry(installPerM2: 900, installFixed: nil, annualPerM2: 8, annualFixed: nil, annualPerAnimal: nil),
        "smokehouse": ObjectCostEntry(installPerM2: nil, installFixed: 600, annualPerM2: nil, annualFixed: 20, annualPerAnimal: nil),
        "workshop": ObjectCostEntry(installPerM2: 350, installFixed: nil, annualPerM2: 6, annualFixed: nil, annualPerAnimal: nil),
        "rainwater-cistern": ObjectCostEntry(installPerM2: nil, installFixed: 1000, annualPerM2: nil, annualFixed: 30, annualPerAnimal: nil),
        "dock": ObjectCostEntry(installPerM2: 400, installFixed: nil, annualPerM2: nil, annualFixed: 60, annualPerAnimal: nil),
        "micro-hydro": ObjectCostEntry(installPerM2: nil, installFixed: 3500, annualPerM2: nil, annualFixed: 150, annualPerAnimal: nil),
    ]

    public static let objectCategoryFallbackCost: [ObjectCategory: ObjectCostEntry] = [
        .storage: ObjectCostEntry(installPerM2: 280, installFixed: nil, annualPerM2: 5, annualFixed: nil, annualPerAnimal: nil),
        .leisure: ObjectCostEntry(installPerM2: 150, installFixed: nil, annualPerM2: 4, annualFixed: nil, annualPerAnimal: nil),
        .energy: ObjectCostEntry(installPerM2: nil, installFixed: 1500, annualPerM2: nil, annualFixed: 60, annualPerAnimal: nil),
        .water: ObjectCostEntry(installPerM2: nil, installFixed: 1200, annualPerM2: nil, annualFixed: 50, annualPerAnimal: nil),
        .utility: ObjectCostEntry(installPerM2: nil, installFixed: 800, annualPerM2: nil, annualFixed: 40, annualPerAnimal: nil),
        .animal: ObjectCostEntry(installPerM2: 100, installFixed: nil, annualPerM2: nil, annualFixed: 100, annualPerAnimal: nil),
    ]

    public static let pathCostPerM2: [PathSurface: (install: Double, annual: Double)] = [
        .paved: (install: 45, annual: 1),
        .gravel: (install: 10, annual: 0.3),
        .mulch: (install: 6, annual: 0.5),
        .grass: (install: 3, annual: 0.4),
    ]

    public static let fenceCostPerM: [FenceType: (install: Double, annual: Double)] = [
        .perimeter: (install: 18, annual: 0.5),
        .paddock: (install: 12, annual: 0.3),
        .garden: (install: 9, annual: 0.2),
        .decorative: (install: 14, annual: 0.3),
    ]

    public static func region(id: String) -> CostRegion {
        costRegions.first { $0.id == id } ?? costRegions[0]
    }
}
