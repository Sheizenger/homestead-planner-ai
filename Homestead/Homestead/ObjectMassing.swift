//
//  ObjectMassing.swift
//  Homestead
//
//  How each catalog entry is built in the axonometric view: how tall it
//  stands and which kit of parts it is drawn from. The engine models
//  footprints only — it plans land use, not architecture — so this lives in
//  the view layer that needs it rather than becoming engine data nothing
//  else would read.
//

import Foundation
import HomesteadEngine

enum Massing {
    enum Form {
        /// Walls to the eaves, then a pitched roof with gable ends: the
        /// default for anything with a roof over it.
        case gabled(eaves: Double, ridge: Double)
        /// Same shape, glazed — low walls and a translucent roof.
        case glass(eaves: Double, ridge: Double)
        /// Upright cylinder: tanks, cisterns, well rings.
        case cylinder(height: Double, radiusScale: Double)
        /// Flat-topped box, for kit with no roof worth drawing.
        case block(height: Double)
        /// Painted on the ground — paths, paddocks, water, roof-mounted kit.
        case flat(height: Double)
        /// Rows of planting, drawn as raised beds with crops on them.
        case rows(height: Double, conifer: Bool)
        /// Canopies on trunks.
        case canopy(height: Double, radius: Double, conifer: Bool)
    }

    static func form(for object: PlanObject) -> Form {
        if object.metadata["roofMounted"]?.boolValue == true { return .flat(height: 0.35) }
        if let specific = forms[object.typeId] { return specific }

        switch object.category {
        case .foodAnnual:
            return .rows(height: 0.45, conifer: false)
        case .foodPerennial:
            return .rows(height: 1.1, conifer: false)
        case .access, .path, .fence, .futureExpansion:
            return .flat(height: 0.05)
        case .water:
            return .flat(height: 0.2)
        case .residential, .animal, .storage, .leisure:
            return .gabled(eaves: 2.4, ridge: 3.8)
        default:
            return .block(height: 2.4)
        }
    }

    private static let forms: [String: Form] = [
        // Roofed
        "house": .gabled(eaves: 3.4, ridge: 6.4),
        "house-l": .gabled(eaves: 3.4, ridge: 6.4),
        "barn": .gabled(eaves: 4.0, ridge: 7.2),
        "workshop": .gabled(eaves: 2.8, ridge: 4.0),
        "garage": .gabled(eaves: 2.6, ridge: 3.4),
        "shed": .gabled(eaves: 2.0, ridge: 2.9),
        "woodshed": .gabled(eaves: 1.9, ridge: 2.6),
        "banya": .gabled(eaves: 2.3, ridge: 3.4),
        "smokehouse": .gabled(eaves: 2.0, ridge: 3.0),
        "cellar": .gabled(eaves: 0.7, ridge: 1.6),
        "gazebo": .gabled(eaves: 2.2, ridge: 3.2),
        "poultry-coop": .gabled(eaves: 1.6, ridge: 2.4),
        "goat-shelter": .gabled(eaves: 2.0, ridge: 2.9),
        "apiary": .gabled(eaves: 0.8, ridge: 1.2),

        // Glazed
        "greenhouse": .glass(eaves: 1.8, ridge: 3.2),
        "hydroponic-tower": .glass(eaves: 2.0, ridge: 2.8),

        // Round
        "water-tank": .cylinder(height: 3.0, radiusScale: 0.46),
        "rainwater-cistern": .cylinder(height: 2.4, radiusScale: 0.46),
        "well": .cylinder(height: 0.9, radiusScale: 0.42),
        "compost": .cylinder(height: 1.1, radiusScale: 0.44),

        // Plain kit
        "battery-room": .block(height: 2.4),
        "inverter-room": .block(height: 2.2),
        "generator": .block(height: 1.5),
        "pump": .block(height: 1.3),

        // Ground
        "solar-array": .flat(height: 0.3),
        "septic": .flat(height: 0.2),
        "patio": .flat(height: 0.1),
        "pool": .flat(height: 0.1),
        "dock": .flat(height: 0.4),
        "goat-paddock": .flat(height: 0.05),

        // Planted
        "raised-beds": .rows(height: 0.55, conifer: false),
        "vineyard": .rows(height: 1.8, conifer: false),
        "berry-rows": .rows(height: 1.1, conifer: false),
        "orchard-trees": .canopy(height: 4.4, radius: 1.7, conifer: false),
    ]

    /// Roof-mounted kit sits on whatever it was placed on, so it needs that
    /// building's roof height rather than the ground — otherwise the solar
    /// array ends up embedded in the lawn under the house it belongs to.
    static func baseElevation(for object: PlanObject, among objects: [PlanObject]) -> Double {
        guard object.metadata["roofMounted"]?.boolValue == true else { return 0 }
        let host = objects.first { other in
            other.id != object.id
                && other.metadata["roofMounted"]?.boolValue != true
                && Polygon.contains(object.transform.center, polygon: other.transform.corners)
        }
        guard let host else { return 0 }
        switch form(for: host) {
        case .gabled(let eaves, let ridge), .glass(let eaves, let ridge):
            // On the slope, a little above the eaves.
            return eaves + (ridge - eaves) * 0.35
        case .block(let height), .cylinder(let height, _), .flat(let height), .rows(let height, _):
            return height
        case .canopy(let height, _, _):
            return height
        }
    }

    /// Roofs are what make the reference illustrations read as buildings, so
    /// they get their own hues rather than a shade of the category fill.
    static func roofColor(for object: PlanObject) -> (light: UInt32, dark: UInt32) {
        switch object.typeId {
        case "house", "house-l": return (0xc4553f, 0x8f3d2d)
        case "barn": return (0x8c3b2f, 0x6b2c23)
        case "garage", "workshop": return (0x4a5b6b, 0x36434f)
        case "banya", "smokehouse": return (0x7a4a3a, 0x5c382c)
        case "gazebo": return (0x6b5b8a, 0x4e4266)
        case "poultry-coop", "goat-shelter": return (0x9a6b4a, 0x734f37)
        default: return (0x7d6b56, 0x5c4e3f)
        }
    }
}
