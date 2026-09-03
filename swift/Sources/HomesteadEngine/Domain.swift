import Foundation

// The plan model, ported from `src/domain/types.ts`. Property names match the
// JSON the TypeScript engine emits, so a fixture decodes into these types
// directly and a whole layout can be compared in one expression.
//
// Two shapes are deliberately absent. `LayoutVariant.id` and its undo history
// belong to the document layer, not to a pure generator, and
// `AnalyticsSnapshot.computedAt` is a fossil of storing analytics that are now
// derived — see AGENTS.md.

public enum ZoneCategory: String, CaseIterable, Codable, Sendable {
    case residential
    case access
    case foodAnnual = "food-annual"
    case foodPerennial = "food-perennial"
    case greenhouse
    case animal
    case utility
    case water
    case energy
    case storage
    case leisure
    case futureExpansion = "future-expansion"
}

/// Zone categories plus the two that only ever appear as layers.
public enum ObjectCategory: String, CaseIterable, Codable, Sendable {
    case residential
    case access
    case foodAnnual = "food-annual"
    case foodPerennial = "food-perennial"
    case greenhouse
    case animal
    case utility
    case water
    case energy
    case storage
    case leisure
    case futureExpansion = "future-expansion"
    case fence
    case path

    public init?(zone: ZoneCategory) {
        self.init(rawValue: zone.rawValue)
    }

    public var zoneCategory: ZoneCategory? {
        ZoneCategory(rawValue: rawValue)
    }
}

public enum PlanningMode: String, CaseIterable, Codable, Sendable {
    case productionMax = "production-max"
    case minimumMaintenance = "minimum-maintenance"
    case beautyBalanced = "beauty-balanced"
    case safetyFirst = "safety-first"
}

public enum ClimateZone: String, CaseIterable, Codable, Sendable {
    case temperate, continental, mediterranean, arid, subtropical, cold
}

public enum TerrainSlope: String, CaseIterable, Codable, Sendable {
    case flat, gentle, steep
}

public enum SoilType: String, CaseIterable, Codable, Sendable {
    case loam, clay, sandy, rocky, unknown
}

public enum WaterfrontType: String, CaseIterable, Codable, Sendable {
    case river, lake, pond
}

public enum PlotEdge: String, CaseIterable, Codable, Sendable {
    case north, south, east, west
}

public struct Waterfront: Equatable, Codable, Sendable {
    public var type: WaterfrontType
    /// Which boundary edge the water runs along.
    public var edge: PlotEdge
    /// How much of the plot's depth from that edge is water.
    public var widthM: Double
    /// River only — for micro-hydro feasibility.
    public var flowSpeedMps: Double?
    /// River or lake outlet — for micro-hydro feasibility.
    public var elevationDropM: Double?

    public init(
        type: WaterfrontType,
        edge: PlotEdge,
        widthM: Double,
        flowSpeedMps: Double? = nil,
        elevationDropM: Double? = nil
    ) {
        self.type = type
        self.edge = edge
        self.widthM = widthM
        self.flowSpeedMps = flowSpeedMps
        self.elevationDropM = elevationDropM
    }
}

/// A single linear grade across the plot: elevation 0 at the edge opposite
/// `highEdge`, rising to `dropM` at it. A coarse stand-in for a survey, but
/// enough to site septic downhill of the house and to give micro-hydro a real
/// head figure instead of a guess.
public struct PlotElevation: Equatable, Codable, Sendable {
    public var highEdge: PlotEdge
    public var dropM: Double

    public init(highEdge: PlotEdge, dropM: Double) {
        self.highEdge = highEdge
        self.dropM = dropM
    }
}

public struct AnimalRequest: Equatable, Codable, Sendable {
    public var type: String
    public var count: Int

    public init(type: String, count: Int) {
        self.type = type
        self.count = count
    }
}

public enum HouseSizePreset: String, CaseIterable, Codable, Sendable {
    case small, medium, large
}

public enum HouseShape: String, CaseIterable, Codable, Sendable {
    case rect, lshape
}

public struct StructuredInputs: Equatable, Codable, Sendable {
    public var householdSize: Int
    public var climateZone: ClimateZone
    public var terrainSlope: TerrainSlope
    public var soilType: SoilType
    public var waterSources: [String]
    public var gridPower: Bool
    /// Ranked, highest priority first.
    public var priorities: [PlanningMode]
    public var animals: [AnimalRequest]
    public var crops: [String]
    public var infrastructure: [String]
    /// 0 = utilitarian, 100 = ornamental.
    public var aestheticPreference: Double
    public var houseSizePreset: HouseSizePreset
    public var houseShape: HouseShape

    public init(
        householdSize: Int = 2,
        climateZone: ClimateZone = .temperate,
        terrainSlope: TerrainSlope = .flat,
        soilType: SoilType = .loam,
        waterSources: [String] = [],
        gridPower: Bool = true,
        priorities: [PlanningMode] = [.beautyBalanced],
        animals: [AnimalRequest] = [],
        crops: [String] = [],
        infrastructure: [String] = [],
        aestheticPreference: Double = 50,
        houseSizePreset: HouseSizePreset = .medium,
        houseShape: HouseShape = .rect
    ) {
        self.householdSize = householdSize
        self.climateZone = climateZone
        self.terrainSlope = terrainSlope
        self.soilType = soilType
        self.waterSources = waterSources
        self.gridPower = gridPower
        self.priorities = priorities
        self.animals = animals
        self.crops = crops
        self.infrastructure = infrastructure
        self.aestheticPreference = aestheticPreference
        self.houseSizePreset = houseSizePreset
        self.houseShape = houseShape
    }
}

public struct Brief: Equatable, Codable, Sendable {
    public var structuredInputs: StructuredInputs
    public var freeText: String
    public var unrecognizedTerms: [String]?

    public init(structuredInputs: StructuredInputs, freeText: String = "", unrecognizedTerms: [String]? = nil) {
        self.structuredInputs = structuredInputs
        self.freeText = freeText
        self.unrecognizedTerms = unrecognizedTerms
    }
}

public struct ExistingObject: Equatable, Codable, Sendable {
    public var id: String
    public var type: String
    public var transform: Transform
    public var label: String

    public init(id: String, type: String, transform: Transform, label: String) {
        self.id = id
        self.type = type
        self.transform = transform
        self.label = label
    }
}

public struct Plot: Equatable, Codable, Sendable {
    public var id: String
    /// Polygon in metres; winding direction does not matter.
    public var boundary: [Point]
    /// Rotation of "up" relative to true north.
    public var northAngleDeg: Double
    public var climateZone: ClimateZone
    public var terrainSlope: TerrainSlope
    public var soilType: SoilType
    public var waterSources: [String]
    public var gridPower: Bool
    public var waterfront: Waterfront?
    public var elevation: PlotElevation?
    public var existingObjects: [ExistingObject]

    public init(
        id: String = "plot",
        boundary: [Point],
        northAngleDeg: Double = 0,
        climateZone: ClimateZone = .temperate,
        terrainSlope: TerrainSlope = .flat,
        soilType: SoilType = .loam,
        waterSources: [String] = [],
        gridPower: Bool = true,
        waterfront: Waterfront? = nil,
        elevation: PlotElevation? = nil,
        existingObjects: [ExistingObject] = []
    ) {
        self.id = id
        self.boundary = boundary
        self.northAngleDeg = northAngleDeg
        self.climateZone = climateZone
        self.terrainSlope = terrainSlope
        self.soilType = soilType
        self.waterSources = waterSources
        self.gridPower = gridPower
        self.waterfront = waterfront
        self.elevation = elevation
        self.existingObjects = existingObjects
    }

    /// The bounding box of the boundary. A plot always has at least three
    /// points in practice; an empty one has no extent to report.
    public var bounds: Rect? { Rect(bounding: boundary) }
}

public struct Zone: Equatable, Codable, Sendable {
    public var id: String
    public var category: ZoneCategory
    /// Polygon in absolute plot coordinates.
    public var boundary: [Point]
    public var label: String
    public var colorOverride: String?
    public var metadata: [String: JSONValue]
    public var locked: Bool

    public init(
        id: String,
        category: ZoneCategory,
        boundary: [Point],
        label: String,
        colorOverride: String? = nil,
        metadata: [String: JSONValue] = [:],
        locked: Bool = false
    ) {
        self.id = id
        self.category = category
        self.boundary = boundary
        self.label = label
        self.colorOverride = colorOverride
        self.metadata = metadata
        self.locked = locked
    }
}

public struct PlanObject: Equatable, Codable, Sendable {
    public var id: String
    public var zoneId: String?
    /// References an `ObjectLibrary` catalog entry.
    public var typeId: String
    public var category: ObjectCategory
    public var transform: Transform
    public var label: String
    public var locked: Bool
    public var layerId: ObjectCategory
    public var metadata: [String: JSONValue]

    public init(
        id: String,
        zoneId: String? = nil,
        typeId: String,
        category: ObjectCategory,
        transform: Transform,
        label: String,
        locked: Bool = false,
        layerId: ObjectCategory,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.zoneId = zoneId
        self.typeId = typeId
        self.category = category
        self.transform = transform
        self.label = label
        self.locked = locked
        self.layerId = layerId
        self.metadata = metadata
    }
}

public enum PathSurface: String, CaseIterable, Codable, Sendable {
    case gravel, paved, mulch, grass
}

public enum PathCategory: String, CaseIterable, Codable, Sendable {
    case access, service
}

public struct PathEntity: Equatable, Codable, Sendable {
    public var id: String
    public var points: [Point]
    public var widthM: Double
    public var surfaceType: PathSurface
    public var category: PathCategory

    public init(id: String, points: [Point], widthM: Double, surfaceType: PathSurface, category: PathCategory) {
        self.id = id
        self.points = points
        self.widthM = widthM
        self.surfaceType = surfaceType
        self.category = category
    }
}

public enum FenceType: String, CaseIterable, Codable, Sendable {
    case perimeter, paddock, garden, decorative
}

public struct Fence: Equatable, Codable, Sendable {
    public var id: String
    public var points: [Point]
    public var fenceType: FenceType
    public var gated: Bool

    public init(id: String, points: [Point], fenceType: FenceType, gated: Bool) {
        self.id = id
        self.points = points
        self.fenceType = fenceType
        self.gated = gated
    }
}

public enum UtilityKind: String, CaseIterable, Codable, Sendable {
    case power, water
}

public struct UtilityNode: Equatable, Codable, Sendable {
    public var id: String
    /// The object this node stands for. Position resolves from it live, so a
    /// dragged object keeps its hookup lines attached.
    public var objectId: String
    /// The object's `typeId`, e.g. `solar-array`.
    public var type: String
    public var kind: UtilityKind
    /// Ids of nodes this one has a direct hookup line to.
    public var connections: [String]

    public init(id: String, objectId: String, type: String, kind: UtilityKind, connections: [String]) {
        self.id = id
        self.objectId = objectId
        self.type = type
        self.kind = kind
        self.connections = connections
    }
}

public enum WarningSeverity: String, CaseIterable, Codable, Sendable {
    case info, caution, critical
}

public struct SuggestedFix: Equatable, Codable, Sendable {
    public var label: String
    public var action: String

    public init(label: String, action: String) {
        self.label = label
        self.action = action
    }
}

public struct Warning: Equatable, Codable, Sendable {
    public var id: String
    public var severity: WarningSeverity
    /// English fallback, used when `messageKey` is absent.
    public var message: String
    public var messageKey: String?
    public var messageParams: [String: JSONValue]?
    public var ruleId: String
    public var objectIds: [String]
    public var suggestedFix: SuggestedFix?

    public init(
        id: String,
        severity: WarningSeverity,
        message: String,
        messageKey: String? = nil,
        messageParams: [String: JSONValue]? = nil,
        ruleId: String,
        objectIds: [String],
        suggestedFix: SuggestedFix? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.messageKey = messageKey
        self.messageParams = messageParams
        self.ruleId = ruleId
        self.objectIds = objectIds
        self.suggestedFix = suggestedFix
    }
}

public struct CategoryArea: Equatable, Codable, Sendable {
    public var category: ZoneCategory
    public var areaM2: Double
    public var percent: Double

    public init(category: ZoneCategory, areaM2: Double, percent: Double) {
        self.category = category
        self.areaM2 = areaM2
        self.percent = percent
    }
}

public struct AnalyticsSnapshot: Equatable, Codable, Sendable {
    public var totalAreaM2: Double
    public var allocatedAreaM2: Double
    public var unallocatedAreaM2: Double
    public var byCategory: [CategoryArea]
    /// 0–100.
    public var estimatedFoodProductionScore: Double
    /// 0–100, higher means more upkeep.
    public var maintenanceComplexityScore: Double

    public init(
        totalAreaM2: Double,
        allocatedAreaM2: Double,
        unallocatedAreaM2: Double,
        byCategory: [CategoryArea],
        estimatedFoodProductionScore: Double,
        maintenanceComplexityScore: Double
    ) {
        self.totalAreaM2 = totalAreaM2
        self.allocatedAreaM2 = allocatedAreaM2
        self.unallocatedAreaM2 = unallocatedAreaM2
        self.byCategory = byCategory
        self.estimatedFoodProductionScore = estimatedFoodProductionScore
        self.maintenanceComplexityScore = maintenanceComplexityScore
    }
}

/// What the generator produces: one complete plan, and nothing about identity
/// or editing history. The document layer wraps this with an id, a
/// manually-edited badge, and an undo stack.
public struct Layout: Equatable, Codable, Sendable {
    public var strategyLabel: String
    public var mode: PlanningMode
    public var seed: Int
    public var zones: [Zone]
    public var objects: [PlanObject]
    public var paths: [PathEntity]
    public var fences: [Fence]
    public var utilityNodes: [UtilityNode]
    public var analytics: AnalyticsSnapshot
    public var warnings: [Warning]

    public init(
        strategyLabel: String,
        mode: PlanningMode,
        seed: Int,
        zones: [Zone],
        objects: [PlanObject],
        paths: [PathEntity],
        fences: [Fence],
        utilityNodes: [UtilityNode],
        analytics: AnalyticsSnapshot,
        warnings: [Warning]
    ) {
        self.strategyLabel = strategyLabel
        self.mode = mode
        self.seed = seed
        self.zones = zones
        self.objects = objects
        self.paths = paths
        self.fences = fences
        self.utilityNodes = utilityNodes
        self.analytics = analytics
        self.warnings = warnings
    }
}
