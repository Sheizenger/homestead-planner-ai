//
//  ObjectSymbols.swift
//  Homestead
//
//  A standard SF Symbol per catalog type, so a shape says what it is before
//  anyone reads its label — and so the 3D view, where labels are harder to
//  place, stays readable at a glance.
//
//  Deliberately long-established symbol names only: an unknown name draws
//  nothing rather than crashing, but "nothing" is exactly the failure this
//  is meant to prevent.
//

import SwiftUI
import HomesteadEngine

enum ObjectSymbols {
    static func name(for object: PlanObject) -> String {
        if let specific = byType[object.typeId] { return specific }
        return byCategory[object.category] ?? "square.dashed"
    }

    private static let byType: [String: String] = [
        "house": "house.fill",
        "house-l": "house.fill",
        "shed": "shippingbox.fill",
        "woodshed": "shippingbox.fill",
        "barn": "building.2.fill",
        "garage": "car.fill",
        "workshop": "wrench.and.screwdriver.fill",
        "cellar": "archivebox.fill",
        "banya": "flame.fill",
        "smokehouse": "smoke.fill",
        "gazebo": "umbrella.fill",
        "patio": "sun.horizon.fill",
        "pool": "figure.pool.swim",

        "greenhouse": "leaf.fill",
        "hydroponic-tower": "drop.circle.fill",
        "orchard-trees": "tree.fill",
        "berry-rows": "leaf.circle.fill",
        "vineyard": "leaf.circle",
        "raised-beds": "square.grid.3x3.fill",
        "potato-area": "circle.grid.2x2.fill",
        "vegetable-area": "carrot.fill",
        "grain-field": "aqi.medium",
        "compost": "arrow.3.trianglepath",

        "poultry-coop": "bird.fill",
        "goat-shelter": "pawprint.fill",
        "goat-paddock": "pawprint",
        "apiary": "hexagon.fill",

        "well": "drop.fill",
        "pump": "gauge",
        "water-tank": "cylinder.fill",
        "rainwater-cistern": "cylinder.fill",
        "septic": "arrow.down.circle.fill",
        "dock": "ferry.fill",
        "micro-hydro": "water.waves",

        "solar-array": "sun.max.fill",
        "battery-room": "battery.100",
        "inverter-room": "bolt.fill",
        "generator": "bolt.circle.fill",
    ]

    private static let byCategory: [ObjectCategory: String] = [
        .residential: "house.fill",
        .access: "figure.walk",
        .foodAnnual: "leaf.fill",
        .foodPerennial: "tree.fill",
        .greenhouse: "leaf.fill",
        .animal: "pawprint.fill",
        .utility: "gearshape.fill",
        .water: "drop.fill",
        .energy: "bolt.fill",
        .storage: "shippingbox.fill",
        .leisure: "sun.horizon.fill",
        .futureExpansion: "square.dashed",
        .fence: "square.dashed",
        .path: "figure.walk",
    ]
}
