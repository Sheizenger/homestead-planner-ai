import Foundation

/// Category strings (e.g. `animal`) and specific catalog type ids (e.g.
/// `well`, `septic`) both work as matchers — a single list drives both
/// placement scoring (`Placement.swift`) and post-hoc warnings, per the
/// TypeScript handoff note's "single source of truth". Ported from
/// `src/domain/constraints.ts`, generated from its data rather than
/// retyped — `ConstraintsParityTests` holds this against that source.
public struct Constraint: Equatable, Sendable {
    public let id: String
    public let kind: ConstraintKind
    public let subjectTypes: [String]
    public let relatedTypes: [String]
    /// `separation`/`safety` rules: violated closer than this.
    public let minDistance: Double?
    /// `adjacency` rules: violated farther than this.
    public let maxDistance: Double?
    /// Hard constraints are enforced as placement filters, not just warnings.
    public let hard: Bool
    public let severity: WarningSeverity
    public let message: String
}

public enum ConstraintKind: String, CaseIterable, Codable, Sendable {
    case adjacency, separation, sunlight, access, safety
}

public struct BoundarySetback: Equatable, Sendable {
    public let id: String
    /// Type ids or categories this setback applies to.
    public let appliesTo: [String]
    public let minDistanceM: Double
    public let severity: WarningSeverity
    public let message: String
}

public enum Constraints {
    /// True if `entry`'s id or category appears in `list` — the matcher both
    /// placement and warnings use to test a `Constraint` or
    /// `BoundarySetback`'s `subjectTypes`/`relatedTypes`/`appliesTo`.
    public static func matches(_ entry: ObjectLibrary.Entry, _ list: [String]) -> Bool {
        list.contains(entry.id) || list.contains(entry.category.rawValue)
    }

    public static let all: [Constraint] = [
        Constraint(
            id: "well-septic-separation",
            kind: .separation,
            subjectTypes: ["well"],
            relatedTypes: ["septic"],
            minDistance: 15,
            maxDistance: nil,
            hard: true,
            severity: .critical,
            message: "Well is closer than the 15 m safe minimum separation from the septic system."
        ),
        Constraint(
            id: "well-tank-water-quality",
            kind: .separation,
            subjectTypes: ["well"],
            relatedTypes: ["compost"],
            minDistance: 10,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Well is close to the compost yard; runoff could affect water quality."
        ),
        Constraint(
            id: "animal-residential-separation",
            kind: .separation,
            subjectTypes: ["animal"],
            relatedTypes: ["residential"],
            minDistance: 10,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Animal zone is close to the house; expect noise and odor at this distance."
        ),
        Constraint(
            id: "animal-leisure-separation",
            kind: .separation,
            subjectTypes: ["animal"],
            relatedTypes: ["leisure"],
            minDistance: 12,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Animal zone is close to a leisure area; odor may reduce comfort there."
        ),
        Constraint(
            id: "compost-residential-separation",
            kind: .separation,
            subjectTypes: ["compost"],
            relatedTypes: ["residential"],
            minDistance: 6,
            maxDistance: nil,
            hard: false,
            severity: .info,
            message: "Compost yard is close to the house."
        ),
        Constraint(
            id: "compost-leisure-separation",
            kind: .separation,
            subjectTypes: ["compost"],
            relatedTypes: ["leisure"],
            minDistance: 8,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Compost yard is close to a leisure area; odor may be noticeable."
        ),
        Constraint(
            id: "generator-noise-separation",
            kind: .separation,
            subjectTypes: ["generator"],
            relatedTypes: ["residential", "leisure"],
            minDistance: 8,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Backup generator is close to a quiet zone; expect noise when running."
        ),
        Constraint(
            id: "kitchen-garden-adjacency",
            kind: .adjacency,
            subjectTypes: ["raised-beds"],
            relatedTypes: ["residential"],
            minDistance: nil,
            maxDistance: 20,
            hard: false,
            severity: .info,
            message: "Kitchen garden is far from the house, adding daily walking distance."
        ),
        Constraint(
            id: "greenhouse-utility-adjacency",
            kind: .adjacency,
            subjectTypes: ["greenhouse", "hydroponic-tower"],
            relatedTypes: ["water", "energy"],
            minDistance: nil,
            maxDistance: 30,
            hard: false,
            severity: .info,
            message: "Greenhouse is far from water/power utilities, complicating irrigation and heating runs."
        ),
        Constraint(
            id: "solar-battery-adjacency",
            kind: .adjacency,
            subjectTypes: ["solar-array"],
            relatedTypes: ["battery-room"],
            minDistance: nil,
            maxDistance: 12,
            hard: false,
            severity: .caution,
            message: "Solar array is far from the battery room, increasing cable losses and cost."
        ),
        Constraint(
            id: "well-pump-adjacency",
            kind: .adjacency,
            subjectTypes: ["well"],
            relatedTypes: ["pump"],
            minDistance: nil,
            maxDistance: 8,
            hard: false,
            severity: .caution,
            message: "Well is far from the pump house."
        ),
        Constraint(
            id: "pump-tank-adjacency",
            kind: .adjacency,
            subjectTypes: ["pump"],
            relatedTypes: ["water-tank"],
            minDistance: nil,
            maxDistance: 10,
            hard: false,
            severity: .info,
            message: "Pump is far from the water tank."
        ),
        Constraint(
            id: "fire-house-outbuilding-separation",
            kind: .safety,
            subjectTypes: ["house", "house-l"],
            relatedTypes: ["barn", "shed", "woodshed", "goat-shelter", "poultry-coop", "banya", "smokehouse"],
            minDistance: 8,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Fire-safety guidance recommends greater separation between the house and combustible outbuildings (typically 8-15 m depending on materials)."
        ),
        Constraint(
            id: "fire-outbuilding-mutual-separation",
            kind: .safety,
            subjectTypes: ["barn", "shed", "woodshed", "goat-shelter", "poultry-coop", "banya", "smokehouse"],
            relatedTypes: ["barn", "shed", "woodshed", "goat-shelter", "poultry-coop", "banya", "smokehouse"],
            minDistance: 6,
            maxDistance: nil,
            hard: false,
            severity: .info,
            message: "Fire-safety guidance recommends at least 6 m between combustible outbuildings."
        ),
        Constraint(
            id: "banya-woodshed-clearance",
            kind: .safety,
            subjectTypes: ["banya", "smokehouse"],
            relatedTypes: ["woodshed"],
            minDistance: 5,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "A wood-fired firebox this close to stored firewood is a fire risk."
        ),
        Constraint(
            id: "apiary-people-separation",
            kind: .safety,
            subjectTypes: ["apiary"],
            relatedTypes: ["leisure", "residential"],
            minDistance: 8,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Beehives this close to a house entrance or leisure area risk stings from foraging bees crossing paths with people."
        ),
        Constraint(
            id: "generator-electrical-fire-clearance",
            kind: .safety,
            subjectTypes: ["generator"],
            relatedTypes: ["house", "house-l", "barn", "shed", "woodshed"],
            minDistance: 3,
            maxDistance: nil,
            hard: true,
            severity: .critical,
            message: "Fuel-fired generators need at least 3 m clearance from combustible structures — exhaust heat and fuel are a fire/electrical hazard at this distance."
        ),
        Constraint(
            id: "generator-woodshed-clearance",
            kind: .safety,
            subjectTypes: ["generator"],
            relatedTypes: ["woodshed"],
            minDistance: 5,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Stored firewood this close to a fuel-fired generator is a fire risk."
        ),
        Constraint(
            id: "battery-woodshed-clearance",
            kind: .safety,
            subjectTypes: ["battery-room"],
            relatedTypes: ["woodshed"],
            minDistance: 2,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Battery storage next to firewood is a fire risk; keep some clearance."
        ),
        Constraint(
            id: "pool-electrical-clearance",
            kind: .safety,
            subjectTypes: ["pool"],
            relatedTypes: ["solar-array", "battery-room", "inverter-room", "generator"],
            minDistance: 3,
            maxDistance: nil,
            hard: false,
            severity: .caution,
            message: "Electrical safety codes require clearance between pools and mains-connected electrical equipment."
        ),
        Constraint(
            id: "cistern-house-adjacency",
            kind: .adjacency,
            subjectTypes: ["rainwater-cistern"],
            relatedTypes: ["residential"],
            minDistance: nil,
            maxDistance: 10,
            hard: false,
            severity: .info,
            message: "Rainwater cistern is far from the house, requiring a longer downspout/gutter run."
        ),
        Constraint(
            id: "hydro-battery-adjacency",
            kind: .adjacency,
            subjectTypes: ["micro-hydro"],
            relatedTypes: ["battery-room"],
            minDistance: nil,
            maxDistance: 15,
            hard: false,
            severity: .caution,
            message: "Micro-hydro turbine is far from the battery room, increasing cable losses and cost."
        ),
    ]

    public static let boundarySetbacks: [BoundarySetback] = [
        BoundarySetback(
            id: "setback-house",
            appliesTo: ["house", "house-l"],
            minDistanceM: 3,
            severity: .caution,
            message: "is closer than the typical 3 m property-line setback for a dwelling."
        ),
        BoundarySetback(
            id: "setback-outbuilding",
            appliesTo: ["storage", "animal", "banya"],
            minDistanceM: 4,
            severity: .caution,
            message: "is closer than the typical 4 m setback for outbuildings/animal housing from the neighboring boundary."
        ),
        BoundarySetback(
            id: "setback-perennial",
            appliesTo: ["food-perennial"],
            minDistanceM: 2,
            severity: .info,
            message: "is close enough to the boundary that mature trees/vines may overhang neighboring land."
        ),
        BoundarySetback(
            id: "setback-well",
            appliesTo: ["well"],
            minDistanceM: 5,
            severity: .caution,
            message: "is closer than the typical 5 m sanitary setback for a well from the property line."
        ),
        BoundarySetback(
            id: "setback-septic",
            appliesTo: ["septic"],
            minDistanceM: 2,
            severity: .caution,
            message: "is closer than the typical 2 m setback for a septic system from the property line."
        ),
        BoundarySetback(
            id: "setback-pool",
            appliesTo: ["pool"],
            minDistanceM: 2,
            severity: .info,
            message: "is close to the boundary — keep clearance for maintenance access and safety."
        ),
    ]
}
