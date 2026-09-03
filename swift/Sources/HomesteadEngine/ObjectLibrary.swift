import Foundation

/// The catalog of things that can be placed on a plot, ported from
/// `src/domain/objectLibrary.ts`.
///
/// Data, not a set of types: a generic renderer keyed on `shape` and
/// `category` keeps adding an object cheap. `ObjectLibraryParityTests` holds
/// this against the TypeScript table entry for entry, so a slip in 30 sets of
/// dimensions and flags fails loudly rather than quietly mis-sizing a paddock.
public enum ObjectLibrary {
    public enum Shape: String, CaseIterable, Codable, Sendable {
        case rect, circle, oval, lshape
    }

    public enum SunNeed: String, CaseIterable, Codable, Sendable {
        case full, partial, none
    }

    public enum NoiseLevel: String, CaseIterable, Codable, Sendable {
        case quiet, moderate, loud
    }

    public enum OdorLevel: String, CaseIterable, Codable, Sendable {
        case none, mild, strong
    }

    public struct Entry: Equatable, Sendable {
        public let id: String
        public let label: String
        public let category: ObjectCategory
        public let shape: Shape
        public let defaultSize: Size
        public let minimumSize: Size
        public let sunNeed: SunNeed
        public let noiseLevel: NoiseLevel
        public let odorLevel: OdorLevel
        /// Frequently visited, so placement favours proximity to the house.
        public let needsAccess: Bool
        public let requiresFence: Bool
        public let description: String
    }

    /// The house variants, which anchor every layout.
    public static let houseTypeIDs: Set<String> = ["house", "house-l"]

    public static subscript(id: String) -> Entry? { byID[id] }

    public static func entries(in category: ObjectCategory) -> [Entry] {
        all.filter { $0.category == category }
    }

    private static let byID: [String: Entry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static let all: [Entry] = [
        Entry(
            id: "house",
            label: "House",
            category: .residential,
            shape: .rect,
            defaultSize: Size(width: 12, height: 10),
            minimumSize: Size(width: 6, height: 6),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Primary residence, anchors the plan."
        ),
        Entry(
            id: "house-l",
            label: "House",
            category: .residential,
            shape: .lshape,
            defaultSize: Size(width: 14, height: 11),
            minimumSize: Size(width: 7, height: 6),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "L-shaped residence enclosing a private courtyard corner."
        ),
        Entry(
            id: "gazebo",
            label: "Gazebo",
            category: .leisure,
            shape: .circle,
            defaultSize: Size(width: 4, height: 4),
            minimumSize: Size(width: 2.5, height: 2.5),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Open-sided shelter for outdoor seating."
        ),
        Entry(
            id: "pool",
            label: "Pool",
            category: .leisure,
            shape: .oval,
            defaultSize: Size(width: 9, height: 4.5),
            minimumSize: Size(width: 4, height: 2.5),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: true,
            description: "Swimming pool; full sun and fenced for child safety."
        ),
        Entry(
            id: "garage",
            label: "Garage",
            category: .residential,
            shape: .rect,
            defaultSize: Size(width: 6, height: 6),
            minimumSize: Size(width: 3.5, height: 5),
            sunNeed: .none,
            noiseLevel: .moderate,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Vehicle storage, sited near the road/entry."
        ),
        Entry(
            id: "shed",
            label: "Tool Shed",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 4, height: 3),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "General tool and equipment storage."
        ),
        Entry(
            id: "barn",
            label: "Barn",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 10, height: 8),
            minimumSize: Size(width: 6, height: 5),
            sunNeed: .none,
            noiseLevel: .moderate,
            odorLevel: .mild,
            needsAccess: true,
            requiresFence: false,
            description: "Feed, equipment, and livestock support building."
        ),
        Entry(
            id: "cellar",
            label: "Root Cellar",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 4, height: 4),
            minimumSize: Size(width: 2.5, height: 2.5),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Cool storage for harvested root crops."
        ),
        Entry(
            id: "woodshed",
            label: "Woodshed",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 4, height: 3),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Dry firewood storage, ideally sun/wind exposed."
        ),
        Entry(
            id: "patio",
            label: "Patio",
            category: .leisure,
            shape: .rect,
            defaultSize: Size(width: 6, height: 5),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Outdoor leisure space adjoining the house."
        ),
        Entry(
            id: "greenhouse",
            label: "Greenhouse",
            category: .greenhouse,
            shape: .rect,
            defaultSize: Size(width: 8, height: 5),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Season-extension growing structure, needs full sun and utility access."
        ),
        Entry(
            id: "hydroponic-tower",
            label: "Vertical Hydroponic Towers",
            category: .greenhouse,
            shape: .rect,
            defaultSize: Size(width: 3, height: 2),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Space-efficient intensive vertical growing, usually inside/near greenhouse."
        ),
        Entry(
            id: "raised-beds",
            label: "Raised Beds",
            category: .foodAnnual,
            shape: .rect,
            defaultSize: Size(width: 8, height: 6),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Kitchen-garden style intensive vegetable beds close to the house."
        ),
        Entry(
            id: "vegetable-area",
            label: "Vegetable Area",
            category: .foodAnnual,
            shape: .rect,
            defaultSize: Size(width: 12, height: 10),
            minimumSize: Size(width: 4, height: 4),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Larger annual vegetable production area."
        ),
        Entry(
            id: "potato-area",
            label: "Potato Field",
            category: .foodAnnual,
            shape: .rect,
            defaultSize: Size(width: 15, height: 10),
            minimumSize: Size(width: 5, height: 5),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Staple-crop field, tolerant of distance from the house."
        ),
        Entry(
            id: "grain-field",
            label: "Grain Field",
            category: .foodAnnual,
            shape: .rect,
            defaultSize: Size(width: 20, height: 15),
            minimumSize: Size(width: 8, height: 8),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Extensive staple grain planting, low visit frequency."
        ),
        Entry(
            id: "orchard-trees",
            label: "Orchard",
            category: .foodPerennial,
            shape: .rect,
            defaultSize: Size(width: 18, height: 14),
            minimumSize: Size(width: 6, height: 6),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Fruit trees; casts long-term shade, keep clear of solar/annual beds."
        ),
        Entry(
            id: "berry-rows",
            label: "Berry Rows",
            category: .foodPerennial,
            shape: .rect,
            defaultSize: Size(width: 10, height: 6),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Bramble and cane fruit rows, moderate visit frequency for harvest."
        ),
        Entry(
            id: "vineyard",
            label: "Vineyard",
            category: .foodPerennial,
            shape: .rect,
            defaultSize: Size(width: 16, height: 10),
            minimumSize: Size(width: 6, height: 6),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Trellised vine planting, full sun, south-facing slope preferred."
        ),
        Entry(
            id: "goat-shelter",
            label: "Goat Shelter",
            category: .animal,
            shape: .rect,
            defaultSize: Size(width: 5, height: 4),
            minimumSize: Size(width: 2.5, height: 2.5),
            sunNeed: .partial,
            noiseLevel: .moderate,
            odorLevel: .strong,
            needsAccess: true,
            requiresFence: true,
            description: "Weatherproof shelter inside the goat paddock."
        ),
        Entry(
            id: "goat-paddock",
            label: "Goat Paddock",
            category: .animal,
            shape: .rect,
            defaultSize: Size(width: 16, height: 12),
            minimumSize: Size(width: 8, height: 8),
            sunNeed: .partial,
            noiseLevel: .moderate,
            odorLevel: .strong,
            needsAccess: true,
            requiresFence: true,
            description: "Fenced grazing/containment area, kept downwind of the house."
        ),
        Entry(
            id: "poultry-coop",
            label: "Poultry Coop & Run",
            category: .animal,
            shape: .rect,
            defaultSize: Size(width: 6, height: 5),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .partial,
            noiseLevel: .moderate,
            odorLevel: .mild,
            needsAccess: true,
            requiresFence: true,
            description: "Hen house and run, close enough for daily egg collection."
        ),
        Entry(
            id: "compost",
            label: "Compost Yard",
            category: .utility,
            shape: .rect,
            defaultSize: Size(width: 4, height: 3),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .strong,
            needsAccess: true,
            requiresFence: false,
            description: "Organic waste processing, kept downwind of leisure/dining areas."
        ),
        Entry(
            id: "water-tank",
            label: "Water Tank",
            category: .water,
            shape: .circle,
            defaultSize: Size(width: 3, height: 3),
            minimumSize: Size(width: 1.5, height: 1.5),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: true,
            description: "Bulk water storage, elevated or near the pump for gravity feed."
        ),
        Entry(
            id: "well",
            label: "Well",
            category: .water,
            shape: .circle,
            defaultSize: Size(width: 2, height: 2),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: true,
            description: "Primary water source; must keep a hard minimum distance from septic."
        ),
        Entry(
            id: "pump",
            label: "Pump House",
            category: .water,
            shape: .rect,
            defaultSize: Size(width: 2, height: 2),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .none,
            noiseLevel: .moderate,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Pressurizes well/tank water, sited between well and tank."
        ),
        Entry(
            id: "septic",
            label: "Septic System",
            category: .utility,
            shape: .rect,
            defaultSize: Size(width: 5, height: 4),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .mild,
            needsAccess: false,
            requiresFence: false,
            description: "Wastewater treatment field; hard-separated from wells and water sources."
        ),
        Entry(
            id: "solar-array",
            label: "Solar Panels",
            category: .energy,
            shape: .rect,
            defaultSize: Size(width: 8, height: 5),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .full,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: false,
            description: "Ground-mount PV array; needs unobstructed south-facing exposure."
        ),
        Entry(
            id: "battery-room",
            label: "Battery Room",
            category: .energy,
            shape: .rect,
            defaultSize: Size(width: 3, height: 3),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Energy storage, kept close to inverter and house load center."
        ),
        Entry(
            id: "inverter-room",
            label: "Inverter Room",
            category: .energy,
            shape: .rect,
            defaultSize: Size(width: 2, height: 2),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .none,
            noiseLevel: .moderate,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Power conversion equipment, adjacent to battery room and house."
        ),
        Entry(
            id: "generator",
            label: "Backup Generator",
            category: .energy,
            shape: .rect,
            defaultSize: Size(width: 2, height: 1.5),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .none,
            noiseLevel: .loud,
            odorLevel: .mild,
            needsAccess: true,
            requiresFence: false,
            description: "Fuel-fired backup power; needs clearance and noise separation."
        ),
        Entry(
            id: "apiary",
            label: "Apiary",
            category: .animal,
            shape: .rect,
            defaultSize: Size(width: 5, height: 3),
            minimumSize: Size(width: 2, height: 2),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Beehives for honey and pollination; keep clear of leisure areas and foot traffic."
        ),
        Entry(
            id: "banya",
            label: "Banya",
            category: .leisure,
            shape: .rect,
            defaultSize: Size(width: 5, height: 4),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .partial,
            noiseLevel: .quiet,
            odorLevel: .mild,
            needsAccess: true,
            requiresFence: false,
            description: "Wood-fired sauna/bathhouse; a solid-fuel firebox, so it needs fire-safety clearance like a woodshed."
        ),
        Entry(
            id: "smokehouse",
            label: "Smokehouse",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 2.5, height: 2),
            minimumSize: Size(width: 1.5, height: 1.5),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .strong,
            needsAccess: true,
            requiresFence: false,
            description: "Wood-fired meat/fish smoking; open flame and smoke need fire and odor clearance."
        ),
        Entry(
            id: "workshop",
            label: "Workshop",
            category: .storage,
            shape: .rect,
            defaultSize: Size(width: 6, height: 5),
            minimumSize: Size(width: 3, height: 3),
            sunNeed: .none,
            noiseLevel: .loud,
            odorLevel: .mild,
            needsAccess: true,
            requiresFence: false,
            description: "Power-tool workspace; noisy, kept apart from quiet leisure zones."
        ),
        Entry(
            id: "rainwater-cistern",
            label: "Rainwater Cistern",
            category: .water,
            shape: .circle,
            defaultSize: Size(width: 2.5, height: 2.5),
            minimumSize: Size(width: 1.2, height: 1.2),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: false,
            requiresFence: true,
            description: "Collects roof runoff for irrigation; sited close to the house for short downspout runs."
        ),
        Entry(
            id: "dock",
            label: "Dock",
            category: .leisure,
            shape: .rect,
            defaultSize: Size(width: 2.5, height: 6),
            minimumSize: Size(width: 1.5, height: 3),
            sunNeed: .none,
            noiseLevel: .quiet,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: false,
            description: "Small pier/boat dock; belongs on calm water — a lake, pond, or slow-moving river section."
        ),
        Entry(
            id: "micro-hydro",
            label: "Micro-Hydro Turbine",
            category: .energy,
            shape: .rect,
            defaultSize: Size(width: 2, height: 2),
            minimumSize: Size(width: 1, height: 1),
            sunNeed: .none,
            noiseLevel: .moderate,
            odorLevel: .none,
            needsAccess: true,
            requiresFence: true,
            description: "Small water turbine; needs enough flow speed or elevation drop across the waterfront to generate meaningful power."
        ),
    ]
}
