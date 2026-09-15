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
        /// The barn shape: a steep lower roof slope breaking at a knuckle
        /// into a shallow upper one. Unmistakable, and the reason a barn is
        /// the one building in an isometric farm nobody has to label.
        case gambrel(eaves: Double, knuckle: Double, ridge: Double)
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

    /// What a building is made of. Two gabled boxes of the same size read as
    /// the same thing whatever colour they are; a plank barn under corrugated
    /// iron and a plastered house under tile do not. This is most of what
    /// makes the catalog legible at a glance.
    struct Surfaces {
        var roof: AxoMaterial
        var wall: AxoMaterial
    }

    static func surfaces(for object: PlanObject) -> Surfaces {
        if let specific = surfaceTable[object.typeId] { return specific }
        switch object.category {
        case .residential: return Surfaces(roof: .shingle, wall: .plaster)
        case .animal: return Surfaces(roof: .metalRoof, wall: .plank)
        case .storage: return Surfaces(roof: .metalRoof, wall: .board)
        default: return Surfaces(roof: .shingle, wall: .plank)
        }
    }

    private static let surfaceTable: [String: Surfaces] = [
        "house": Surfaces(roof: .shingle, wall: .plaster),
        "house-l": Surfaces(roof: .shingle, wall: .plaster),
        "barn": Surfaces(roof: .metalRoof, wall: .plank),
        "workshop": Surfaces(roof: .metalRoof, wall: .board),
        "garage": Surfaces(roof: .metalRoof, wall: .board),
        "shed": Surfaces(roof: .metalRoof, wall: .board),
        "woodshed": Surfaces(roof: .thatch, wall: .board),
        "goat-shelter": Surfaces(roof: .shingle, wall: .plank),
        "poultry-coop": Surfaces(roof: .shingle, wall: .plank),
        "banya": Surfaces(roof: .shingle, wall: .plank),
        "smokehouse": Surfaces(roof: .shingle, wall: .brick),
        "cellar": Surfaces(roof: .thatch, wall: .brick),
        "greenhouse": Surfaces(roof: .glass, wall: .glass),
            ]

    /// How tall a thing is for the purpose of casting a shadow — the ridge
    /// for a roof, the canopy top for a tree, near nothing for a path. Flat
    /// features return 0 and cast none: a gravel path with a shadow under it
    /// reads as a floating slab.
    static func shadowHeight(for object: PlanObject) -> Double {
        switch form(for: object) {
        case let .gabled(_, ridge): return ridge
        case let .glass(_, ridge): return ridge * 0.9
        case let .gambrel(_, _, ridge): return ridge
        case let .cylinder(height, _): return height
        case let .block(height): return height
        case .flat: return 0
        case let .rows(height, _): return height
        case let .canopy(height, _, _): return height * 0.85
        }
    }

    static func form(for object: PlanObject) -> Form {
        if object.metadata["roofMounted"]?.boolValue == true { return .flat(height: 0.35) }
        if let specific = forms[object.typeId] { return specific }

        switch object.category {
        case .foodAnnual, .foodPerennial:
            let planting = planting(for: object)
            return .rows(height: planting.bed + planting.height, conifer: false)
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
        "barn": .gambrel(eaves: 3.2, knuckle: 5.4, ridge: 6.8),
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
        case .gambrel(let eaves, _, let ridge):
            return eaves + (ridge - eaves) * 0.35
        case .block(let height), .cylinder(let height, _), .flat(let height), .rows(let height, _):
            return height
        case .canopy(let height, _, _):
            return height
        }
    }

    /// How a bed is planted, in metres.
    ///
    /// The first pass took a single `rows(height:)` number and drew the
    /// foliage at up to 1.5× it on top of a bed already 0.3× proud of the
    /// grass — so a berry row came out near 2 m against a 2.4 m wall, as tall
    /// as the building beside it, and on a thin stem with a tuft it read as a
    /// sapling rather than a bush. Real sizes per crop, and the foliage wider
    /// than it is tall, which is what the references show.
    struct Planting {
        /// How far the tilled bed stands above the grass.
        var bed: Double
        /// Foliage height above the bed.
        var height: Double
        /// Foliage width. Clamped to the row spacing at draw time, so a plant
        /// can never be wider than the gap it grows in.
        var spread: Double
        /// Metres between furrows.
        var rowSpacing: Double
        /// Metres between plants along a furrow.
        var plantSpacing: Double
        /// Tall crops are drawn on a visible stem; low ones are all foliage.
        var stemmed: Bool
    }

    static func planting(for object: PlanObject) -> Planting {
        if let specific = plantings[object.typeId] { return specific }
        switch object.category {
        case .foodPerennial:
            return Planting(bed: 0.15, height: 0.80, spread: 0.65, rowSpacing: 1.2, plantSpacing: 1.1, stemmed: false)
        default:
            return Planting(bed: 0.12, height: 0.30, spread: 0.45, rowSpacing: 0.8, plantSpacing: 0.7, stemmed: false)
        }
    }

    private static let plantings: [String: Planting] = [
        "raised-beds": Planting(bed: 0.35, height: 0.26, spread: 0.40, rowSpacing: 0.7, plantSpacing: 0.55, stemmed: false),
        "vegetable-area": Planting(bed: 0.12, height: 0.30, spread: 0.45, rowSpacing: 0.8, plantSpacing: 0.65, stemmed: false),
        "potato-area": Planting(bed: 0.18, height: 0.38, spread: 0.50, rowSpacing: 0.85, plantSpacing: 0.7, stemmed: false),
        "grain-field": Planting(bed: 0.05, height: 0.80, spread: 0.22, rowSpacing: 0.5, plantSpacing: 0.4, stemmed: true),
        "berry-rows": Planting(bed: 0.15, height: 0.85, spread: 0.70, rowSpacing: 1.3, plantSpacing: 1.0, stemmed: false),
        "vineyard": Planting(bed: 0.12, height: 1.30, spread: 0.55, rowSpacing: 1.9, plantSpacing: 1.2, stemmed: true),
        "hydroponic-tower": Planting(bed: 0.25, height: 1.10, spread: 0.45, rowSpacing: 1.2, plantSpacing: 1.0, stemmed: true),
    ]

    /// Where a grove's trees stand. Shared, because the shadow pass needs the
    /// same positions the drawing pass uses: a grove that casts one big
    /// rectangular shadow for its whole footprint reads as a crate of trees.
    static func grovePositions(for object: PlanObject) -> [Point] {
        let width = object.transform.width
        let depth = object.transform.height
        let columns = min(4, max(1, Int(width / 5)))
        let rows = min(4, max(1, Int(depth / 5)))
        let centre = object.transform.center

        var positions: [Point] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = columns == 1 ? centre.x : centre.x - width / 2 + 1.5 + Double(column) * (width - 3) / Double(columns - 1)
                let y = rows == 1 ? centre.y : centre.y - depth / 2 + 1.5 + Double(row) * (depth - 3) / Double(rows - 1)
                positions.append(Point(x: x, y: y))
            }
        }
        return positions
    }

    /// Foliage is a material, not a category. The 2D plan's category `fill` is
    /// a pale background tint — right for a tinted footprint on a white page,
    /// and the reason the first pass's orchards came out as white cauliflower:
    /// a pale green mixed toward white for the lit lobes is just white.
    static func foliage(for object: PlanObject) -> UInt32 {
        switch object.typeId {
        case "orchard-trees": return 0x4e8f3a
        case "berry-rows": return 0x5f9c37
        case "vineyard": return 0x6a8f3c
        case "grain-field": return 0xd9b74a
        case "potato-area": return 0x59913f
        case "raised-beds", "vegetable-area": return 0x6cae42
        case "hydroponic-tower": return 0x63b86a
        default: return 0x4a8c3d
        }
    }

    static func palette(for object: PlanObject) -> Palette {
        if let specific = palettes[object.typeId] { return specific }
        switch object.category {
        case .residential: return Palette(wall: 0xf0e2c6, roof: 0xc4553f, trim: 0xffffff)
        case .animal: return Palette(wall: 0xd9cdb4, roof: 0x9a6b4a, trim: 0xfaf6ec)
        case .storage: return Palette(wall: 0xb09068, roof: 0x5c6a76, trim: 0xe8e0cf)
        case .leisure: return Palette(wall: 0xe4d6bd, roof: 0x7d8f74, trim: 0xffffff)
        default: return Palette(wall: 0xc9b696, roof: 0x7d6b56, trim: 0xf0e8d8)
        }
    }

    private static let palettes: [String: Palette] = [
        "house": Palette(wall: 0xf5e7c8, roof: 0xc4553f, trim: 0xffffff),
        "house-l": Palette(wall: 0xf5e7c8, roof: 0xc4553f, trim: 0xffffff),
                "barn": Palette(wall: 0xb5442f, roof: 0xe9e4da, trim: 0xffffff),
        "workshop": Palette(wall: 0x9fb0bd, roof: 0x44515e, trim: 0xf2f4f6),
        "garage": Palette(wall: 0xc8cdd2, roof: 0x4a5b6b, trim: 0xffffff),
        "shed": Palette(wall: 0xa8865c, roof: 0x5c6a76, trim: 0xe4d9c4),
        "woodshed": Palette(wall: 0x9a7a52, roof: 0xa08a5e, trim: 0xd8c9a8),
        "cellar": Palette(wall: 0xada597, roof: 0x84906e, trim: 0xdedace),
        "goat-shelter": Palette(wall: 0xe8d9a8, roof: 0x8a5b3a, trim: 0xfaf4e4),
        "poultry-coop": Palette(wall: 0xfaf4e8, roof: 0xc4553f, trim: 0xd8c9a8),
        "banya": Palette(wall: 0xa0774c, roof: 0x6e5647, trim: 0xe0c49a),
        "smokehouse": Palette(wall: 0xa39889, roof: 0x70594a, trim: 0xd8d1c6),
        "gazebo": Palette(wall: 0xf2ece0, roof: 0x6b5b8a, trim: 0xffffff),
        "greenhouse": Palette(wall: 0xdff0f2, roof: 0xbfe3e8, trim: 0x8fb0ba),
        // Equipment. Painted metal rather than the pale category fill, which
        // left a micro-hydro turbine on the plot as a plain white cube.
        "generator": Palette(wall: 0x6f7a80, roof: 0x4d565b, trim: 0xd9dde0),
        "battery-room": Palette(wall: 0x4f5f6e, roof: 0x3a4854, trim: 0xc8d2da),
        "inverter-room": Palette(wall: 0x5d6d7a, roof: 0x44525d, trim: 0xccd6dd),
        "micro-hydro": Palette(wall: 0x3f7a86, roof: 0x2e5b64, trim: 0xd0e6ea),
        "pump": Palette(wall: 0x7a8288, roof: 0x565d62, trim: 0xdadee1),
        "hydroponic-tower": Palette(wall: 0xd6e8e2, roof: 0x9fc4b8, trim: 0xf0f7f4),
        "dock": Palette(wall: 0xb08a5c, roof: 0x8a6a44, trim: 0xd8c2a0),
        "apiary": Palette(wall: 0xf0c765, roof: 0x8a6a3a, trim: 0xfff6d8),
        "water-tank": Palette(wall: 0xd8d2c4, roof: 0xb0a794, trim: 0xf2eee4),
        "rainwater-cistern": Palette(wall: 0xc6d6d8, roof: 0x9db2b5, trim: 0xe8f0f1),
        "well": Palette(wall: 0xa9a196, roof: 0x7d4f3a, trim: 0xe0dad0),
    ]
}
