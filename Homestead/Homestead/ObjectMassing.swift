//
//  ObjectMassing.swift
//  Homestead
//
//  How tall each catalog entry stands, and how it should be massed in the
//  axonometric view. The engine models footprints only — it plans land use,
//  not buildings — so heights live here, in the view layer that needs them,
//  rather than being invented as engine data that nothing else would read.
//

import Foundation
import HomesteadEngine

enum Massing {
    enum Form {
        /// Extruded prism: walls plus a roof face.
        case block(height: Double)
        /// Painted on the ground — paths, paddocks, crop beds, water.
        case flat(height: Double)
        /// Canopies on trunks, laid out like the orchard glyph.
        case canopy(height: Double, radius: Double)
    }

    static func form(for object: PlanObject) -> Form {
        if let specific = heights[object.typeId] { return specific }

        switch object.category {
        case .foodAnnual, .foodPerennial:
            return .flat(height: 0.35)
        case .access, .path, .fence, .futureExpansion:
            return .flat(height: 0.05)
        case .water:
            return .flat(height: 0.2)
        default:
            return .block(height: 3.0)
        }
    }

    private static let heights: [String: Form] = [
        "house": .block(height: 6.2),
        "house-l": .block(height: 6.2),
        "barn": .block(height: 7.0),
        "workshop": .block(height: 3.6),
        "garage": .block(height: 3.2),
        "shed": .block(height: 2.6),
        "woodshed": .block(height: 2.4),
        "banya": .block(height: 3.2),
        "smokehouse": .block(height: 2.8),
        "cellar": .block(height: 1.2),
        "gazebo": .block(height: 3.0),
        "greenhouse": .block(height: 3.0),
        "hydroponic-tower": .block(height: 2.6),
        "poultry-coop": .block(height: 2.2),
        "goat-shelter": .block(height: 2.6),
        "apiary": .block(height: 1.2),
        "battery-room": .block(height: 2.6),
        "inverter-room": .block(height: 2.4),
        "generator": .block(height: 1.6),
        "pump": .block(height: 1.4),
        "water-tank": .block(height: 2.8),
        "rainwater-cistern": .block(height: 2.4),
        "well": .block(height: 1.0),
        "solar-array": .flat(height: 0.3),
        "septic": .flat(height: 0.2),
        "compost": .block(height: 1.1),
        "patio": .flat(height: 0.1),
        "pool": .flat(height: 0.1),
        "dock": .flat(height: 0.4),
        "goat-paddock": .flat(height: 0.05),
        "raised-beds": .flat(height: 0.5),
        "vineyard": .flat(height: 1.8),
        "berry-rows": .flat(height: 1.1),
        "orchard-trees": .canopy(height: 4.2, radius: 1.6),
    ]

    /// Roof-mounted kit sits on whatever it was placed on, so it needs that
    /// building's height rather than the ground — otherwise the array ends up
    /// embedded in the lawn under the house it belongs to.
    static func baseElevation(for object: PlanObject, among objects: [PlanObject]) -> Double {
        guard object.metadata["roofMounted"]?.boolValue == true else { return 0 }
        let host = objects.first { other in
            other.id != object.id
                && other.metadata["roofMounted"]?.boolValue != true
                && Polygon.contains(object.transform.center, polygon: other.transform.corners)
        }
        guard let host, case .block(let height) = form(for: host) else { return 0 }
        return height
    }
}
