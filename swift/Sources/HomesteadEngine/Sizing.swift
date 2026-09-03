import Foundation

/// Translates a brief into footprint-sized program items, ported from
/// `src/engine/sizing.ts`. Pure and array-driven throughout — order here is
/// the order objects get placed in, so it has to match the TypeScript
/// iteration exactly, not just its final set of items.
public enum Sizing {
    public struct ProgramItem: Equatable, Sendable {
        public var typeId: String
        public var size: Size
        /// How many separate instances to place — e.g. two berry rows.
        public var count: Int
        public var metadata: [String: JSONValue]
    }

    private static let cropToType: [String: String] = [
        "potato": "potato-area",
        "grain": "grain-field",
        "vegetable": "vegetable-area",
        "berries": "berry-rows",
        "orchard": "orchard-trees",
        "vineyard": "vineyard",
        "greenhouse": "greenhouse",
        "hydroponic": "hydroponic-tower",
        "raised-beds": "raised-beds",
    ]

    private static let infraToTypes: [String: [String]] = [
        "solar": ["solar-array", "battery-room", "inverter-room"],
        "well": ["well", "pump"],
        "septic": ["septic"],
        "water-tank": ["water-tank"],
        "generator": ["generator"],
        "compost": ["compost"],
        "cellar": ["cellar"],
        "woodshed": ["woodshed"],
        "garage": ["garage"],
        "barn": ["barn"],
        "pool": ["pool"],
        "gazebo": ["gazebo"],
        "apiary": ["apiary"],
        "banya": ["banya"],
        "smokehouse": ["smokehouse"],
        "workshop": ["workshop"],
        "rainwater-cistern": ["rainwater-cistern"],
        "dock": ["dock"],
        "micro-hydro": ["micro-hydro"],
    ]

    private static let modeScale: [PlanningMode: Double] = [
        .productionMax: 1.3,
        .minimumMaintenance: 0.75,
        .beautyBalanced: 1.0,
        .safetyFirst: 0.9,
    ]

    private static let houseSizeScale: [HouseSizePreset: Double] = [
        .small: 0.55,
        .medium: 1,
        .large: 1.65,
    ]

    /// Staple crops (potato/grain/vegetable) scale to household subsistence
    /// need and are held level across modes; surplus/quality-of-life zones
    /// (orchard, berries, vineyard, greenhouse) are what "production-max"
    /// actually grows. Keeping the split legible instead of inflating
    /// everything uniformly is deliberate — the latter starved orchard space
    /// in testing.
    private static func perPersonScale(_ householdSize: Int, base: Double) -> Double {
        base * min(1.8, max(0.6, Double(householdSize) / 3))
    }

    public static func buildProgram(_ inputs: StructuredInputs, mode: PlanningMode) -> [ProgramItem] {
        var items: [ProgramItem] = []
        let foodModeScale = modeScale[mode] ?? 1

        let houseTypeId = inputs.houseShape == .lshape ? "house-l" : "house"
        items.append(sized(houseTypeId, scale: houseSizeScale[inputs.houseSizePreset] ?? 1))
        if inputs.aestheticPreference >= 35 { items.append(sized("patio", scale: 1)) }
        items.append(sized("shed", scale: 1))

        let staples: Set<String> = ["potato-area", "grain-field", "vegetable-area"]
        for crop in inputs.crops {
            guard let typeId = cropToType[crop] else { continue }
            let scale = staples.contains(typeId)
                ? perPersonScale(inputs.householdSize, base: 1)
                : foodModeScale
            items.append(sized(typeId, scale: scale))
        }

        for animal in inputs.animals {
            switch animal.type {
            case "goats" where animal.count > 0:
                let paddockScale = max(1, Double(animal.count) / 4)
                items.append(sized("goat-shelter", scale: max(1, Double(animal.count) / 4) * 0.9))
                items.append(sized(
                    "goat-paddock",
                    scale: paddockScale,
                    metadata: ["animalCount": .number(Double(animal.count)), "animalType": "goats"]
                ))
            case "poultry" where animal.count > 0:
                items.append(sized(
                    "poultry-coop",
                    scale: max(1, Double(animal.count) / 8),
                    metadata: ["animalCount": .number(Double(animal.count)), "animalType": "poultry"]
                ))
            default:
                break
            }
        }

        for infra in inputs.infrastructure {
            guard let typeIds = infraToTypes[infra] else { continue }
            for typeId in typeIds { items.append(sized(typeId, scale: 1)) }
        }

        // Compost is near-universal once any food production is requested.
        if !inputs.crops.isEmpty, !inputs.infrastructure.contains("compost") {
            items.append(sized("compost", scale: 1))
        }

        return items
    }

    private static func sized(_ typeId: String, scale: Double, metadata: [String: JSONValue] = [:]) -> ProgramItem {
        guard let entry = ObjectLibrary[typeId] else {
            preconditionFailure("'\(typeId)' is not in the object catalog")
        }
        let sqrtScale = scale.squareRoot()
        return ProgramItem(
            typeId: typeId,
            size: Size(
                width: max(entry.minimumSize.width, entry.defaultSize.width * sqrtScale),
                height: max(entry.minimumSize.height, entry.defaultSize.height * sqrtScale)
            ),
            count: 1,
            metadata: metadata
        )
    }
}
