import Foundation
import HomesteadEngine

/// What each kind of object is made of, in meshes.
///
/// The old view drew everything from paths and told the difference between a
/// barn and a greenhouse with a roof profile and a texture. This says it with
/// the thing itself: a watermill is a watermill mesh, an orchard is trees, a
/// paddock is a fence with animals' shelter in it. The table is data, so
/// adding an object type is an entry rather than a new drawing routine.
public enum SceneCatalog {

    /// How an object's mass is built.
    public enum Massing: Equatable, Sendable {
        /// A building at its real dimensions, assembled from whichever of
        /// `meshes` fits the footprint with least distortion — split into
        /// bays along its long axis when no single mesh comes close.
        case building(meshes: [String], height: Double)
        /// One mesh, sized by `fit` and standing in the middle.
        case single(model: String, fit: ModelFit)
        /// Meshes strewn across the footprint at roughly this many per square
        /// metre: an orchard, a rough paddock, a berry patch.
        case scatter(models: [String], perSquareMetre: Double, height: Double)
        /// Meshes in rows across the footprint: crops, vines, panels, beds.
        ///
        /// `stretched` says which kind of thing is in the row, and it is not a
        /// detail. A plant repeats at its own size along the row; stretching
        /// one to the length of a field gives a twenty-metre blade of grass,
        /// which is what the first version drew. A hedge or a panel is a
        /// modular row *piece* and stretching is exactly what it is for —
        /// repeating one at uniform scale piles them into a tangle, which is
        /// what the second version drew. Inferring it from the tilt got one
        /// of the two right by accident.
        ///
        /// `tilt` leans each piece back: zero for anything growing, and the
        /// array angle for solar panels, which lying flat read as puddles.
        case rows(
            model: String,
            spacing: Double,
            height: Double,
            alongLongAxis: Bool,
            stretched: Bool = false,
            tilt: Double = 0
        )
        /// A built volume with an optional pitched top: a glasshouse, a store
        /// cut into a bank. For the handful of things no kit contains and no
        /// flat slab can stand in for.
        case volume(colour: Int, wallHeight: Double, ridgeRise: Double, opacity: Double)
        /// A slab with no mesh — paving, decking, a lawn. The renderer builds
        /// a box; nothing in any kit is a 40-square-metre patio and stretching
        /// something that is would look like one.
        case surface(colour: Int, height: Double)
        /// Sunk below grade rather than standing on it: a pool, a cellar.
        case sunken(colour: Int, depth: Double)
    }

    /// Something small standing next to the main mass. Props are most of what
    /// separates a site plan from a place — a car on the drive, bales by the
    /// barn, a boat at the dock.
    public struct Prop: Equatable, Sendable {
        public var model: String
        public var fit: ModelFit
        /// Which way out of the object it stands, as a direction rather than
        /// a distance: (1, 0) is off the east side, (-1, 1) off the
        /// south-west corner. How far out is not a choice — the prop is put
        /// down clear of the footprint and clear of its neighbours.
        ///
        /// It used to be a fraction of the half-extent, which meant every
        /// value under 1.0 placed the prop *inside* the object. A tractor at
        /// 0.7 of a ten-metre barn stood three and a half metres in from the
        /// centre, which is inside the barn, and it looked exactly like a
        /// tractor embedded in a wall. Twelve of the sixteen faults in the
        /// first scene were this one.
        public var direction: (x: Double, y: Double)
        public var yaw: Double
        public var count: Int
        /// True for the handful of props that belong *under* the thing they
        /// go with: stools beneath an open canopy, and nothing else so far.
        public var inside: Bool

        public init(
            _ model: String,
            fit: ModelFit,
            direction: (x: Double, y: Double) = (1, 0),
            yaw: Double = 0,
            count: Int = 1,
            inside: Bool = false
        ) {
            self.model = model
            self.fit = fit
            self.direction = direction
            self.yaw = yaw
            self.count = count
            self.inside = inside
        }

        public static func == (lhs: Prop, rhs: Prop) -> Bool {
            lhs.model == rhs.model && lhs.fit == rhs.fit && lhs.yaw == rhs.yaw
                && lhs.count == rhs.count && lhs.direction == rhs.direction
                && lhs.inside == rhs.inside
        }
    }

    public struct Look: Equatable, Sendable {
        public var massing: Massing
        public var props: [Prop]
        /// Recolour over the kit's atlas, 0xRRGGBB. One texture per kit means
        /// tinting is how two sheds become two different sheds.
        public var tint: Int?

        public init(_ massing: Massing, props: [Prop] = [], tint: Int? = nil) {
            self.massing = massing
            self.props = props
            self.tint = tint
        }
    }

    // MARK: - Mesh sets

    // These sets were first written from the mesh names and were wrong for it:
    // `building-type-p` and `-q` are flat-roofed modern blocks, and picking one
    // for the house drew a homestead with an office building on it. They are
    // named here so nobody puts them back by accident.
    //
    // Every mesh in this kit is grey-walled under a green roof, which is what
    // one texture atlas per kit buys you. Tinting is how a barn becomes red.

    /// Two-storey, pitched, domestic.
    static let houseMeshes = [
        "city/building-type-a", "city/building-type-b", "city/building-type-c",
        "city/building-type-e", "city/building-type-n", "city/building-type-s",
        "city/building-type-t", "city/building-type-u",
    ]
    /// One compact mass under a pitched roof: sheds, coops, stores.
    static let outbuildingMeshes = [
        "city/building-type-k", "city/building-type-r", "city/building-type-m",
        "city/building-type-g", "city/building-type-i",
    ]
    /// Long and low: barns, workshops, garages.
    static let workingMeshes = [
        "city/building-type-h", "city/building-type-j",
        "city/building-type-d", "city/building-type-f",
    ]
    /// Low and single-storey. A garage built from the house meshes comes out
    /// as a second house, which is what it looked like: the same two storeys,
    /// the same dormers, the same front door.
    /// Only the two meshes in the kit whose height is barely half their
    /// width. Everything else here is a two-storey house with two rows of
    /// windows, and shrinking one of those does not make a garage — it makes
    /// a small house, which is what it looked like.
    static let garageMeshes = ["city/building-type-h", "city/building-type-g"]
    /// Flat-roofed and modern. Nothing on a homestead looks like this.
    static let unsuitableMeshes = ["city/building-type-p", "city/building-type-q"]
    static let broadleafTrees = [
        "town/tree", "town/tree-high", "town/tree-crooked", "town/tree-high-round", "forest/tree",
    ]
    static let coniferTrees = ["yard/pine", "yard/pine-crooked", "survival/tree-tall", "survival/tree"]

    // MARK: - The table

    public static func look(for typeId: String) -> Look { table[typeId] ?? fallback }

    public static func look(for object: PlanObject) -> Look { look(for: object.typeId) }

    static let fallback = Look(.single(model: "works/structure-short", fit: .footprint(height: 2.4)))

    static let table: [String: Look] = [
        // Dwellings -----------------------------------------------------
        "house": Look(
            .building(meshes: houseMeshes, height: 6.4),
            props: [Prop("town/tree", fit: .standing(height: 4.5), direction: (0.72, 0.4))],
            tint: 0xEFE3CC
        ),
        "house-l": Look(.building(meshes: houseMeshes, height: 6.4), tint: 0xEFE3CC),
        "banya": Look(.building(meshes: outbuildingMeshes, height: 3.8), tint: 0xC9A97A),
        "smokehouse": Look(.building(meshes: outbuildingMeshes, height: 3.4), tint: 0x8E7B62),

        // Working buildings ---------------------------------------------
        "barn": Look(
            .building(meshes: workingMeshes, height: 7.2),
            props: [
                Prop("yard/hay-bale", fit: .spanning(1.6), direction: (0.68, 0.3), count: 3),
                Prop("vehicles/tractor", fit: .standing(height: 2.6), direction: (0.7, -0.35), yaw: .pi / 2),
                Prop("town/cart", fit: .spanning(2.0), direction: (-0.72, 0.4)),
            ],
            tint: 0xB4503C
        ),
        "workshop": Look(
            .building(meshes: workingMeshes, height: 4.4),
            props: [Prop("survival/workbench", fit: .spanning(1.6), direction: (0.66, 0))],
            tint: 0x9AA2A8
        ),
        "garage": Look(
            .building(meshes: garageMeshes, height: 2.9),
            props: [Prop("vehicles/sedan", fit: .standing(height: 1.5), direction: (0, 1))],
            tint: 0xB6BCC2
        ),
        "shed": Look(.building(meshes: outbuildingMeshes, height: 2.9), tint: 0x9FB08A),
        "woodshed": Look(
            .building(meshes: outbuildingMeshes, height: 2.4),
            props: [Prop("survival/resource-wood", fit: .spanning(1.4), direction: (0, 1), count: 3)],
            tint: 0x8B6F4A
        ),
        "cellar": Look(
            .volume(colour: 0x7E8A72, wallHeight: 1.2, ridgeRise: 0.9, opacity: 1),
            props: [Prop("town/wall-wood-door", fit: .standing(height: 1.7), direction: (0, 0.5))]
        ),
        "greenhouse": Look(.volume(colour: 0xBBE3E8, wallHeight: 1.9, ridgeRise: 1.3, opacity: 0.45)),
        "hydroponic-tower": Look(.building(meshes: outbuildingMeshes, height: 4.4), tint: 0xA8C2A0),
        "gazebo": Look(
            .single(model: "survival/structure-canvas", fit: .inscribed),
            props: [Prop("town/stall-stool", fit: .spanning(0.7), count: 2, inside: true)]
        ),

        // Animals --------------------------------------------------------
        "goat-shelter": Look(.building(meshes: outbuildingMeshes, height: 2.6), tint: 0xC2A06A),
        "goat-paddock": Look(
            .surface(colour: 0x9C8E63, height: 0.02),
            props: [
                Prop("survival/grass-large", fit: .spanning(1.2), count: 7),
                Prop("survival/patch-grass", fit: .spanning(1.6), direction: (-0.5, 0.4), count: 3),
                Prop("yard/hay-bale", fit: .spanning(1.5), direction: (0.6, -0.55)),
            ]
        ),
        "poultry-coop": Look(.building(meshes: outbuildingMeshes, height: 2.4), tint: 0xD8B26A),
        "apiary": Look(
            .surface(colour: 0x88A257, height: 0.02),
            props: [
                Prop("survival/box", fit: .spanning(0.9), count: 5),
                Prop("survival/grass-large", fit: .spanning(0.9), direction: (-0.6, 0.5), count: 2),
            ]
        ),

        // Growing --------------------------------------------------------
        "orchard-trees": Look(.scatter(models: broadleafTrees, perSquareMetre: 0.04, height: 4.8)),
        "berry-rows": Look(.rows(model: "town/hedge", spacing: 1.8, height: 1.1, alongLongAxis: true, stretched: true)),
        "vineyard": Look(.rows(model: "town/poles", spacing: 2.2, height: 1.9, alongLongAxis: true)),
        "raised-beds": Look(.rows(model: "survival/grass", spacing: 1.4, height: 0.55, alongLongAxis: true)),
        "vegetable-area": Look(.rows(model: "survival/grass", spacing: 1.2, height: 0.45, alongLongAxis: true)),
        "potato-area": Look(.rows(model: "survival/grass", spacing: 1.1, height: 0.4, alongLongAxis: true)),
        "grain-field": Look(
            .rows(model: "survival/grass-large", spacing: 1.0, height: 0.9, alongLongAxis: true),
            props: [Prop("yard/hay-bale", fit: .spanning(1.6), direction: (0.7, 0.7), count: 2)]
        ),
        "compost": Look(
            .single(model: "survival/box-large-open", fit: .footprint(height: 1.2)),
            tint: 0x6E5A3C
        ),

        // Water ----------------------------------------------------------
        "well": Look(.single(model: "town/fountain-round", fit: .inscribed)),
        "pump": Look(.single(model: "works/machine", fit: .standing(height: 1.4))),
        "water-tank": Look(.single(model: "survival/barrel", fit: .inscribed), tint: 0x9FB6C4),
        "rainwater-cistern": Look(.single(model: "survival/barrel", fit: .inscribed), tint: 0x6F8A98),
        "septic": Look(.single(model: "works/top-large", fit: .footprint(height: 0.4)), tint: 0x8A8F84),
        "pool": Look(.sunken(colour: 0x3FA9D6, depth: 1.4)),
        "dock": Look(
            .single(model: "water/ramp-wide", fit: .footprint(height: 1.0)),
            props: [Prop("water/boat-row-small", fit: .standing(height: 0.9), direction: (0.0, 0.85))]
        ),
        "micro-hydro": Look(.single(model: "town/watermill", fit: .inscribed)),

        // Power ----------------------------------------------------------
        // `survival/metal-panel` is a corrugated *wall* sheet, and squashing one
        // flat turns its corrugations into a row of shards. `works/top-large`
        // is a flat plate, which is what a photovoltaic panel is.
        "solar-array": Look(
            .rows(model: "works/top-large", spacing: 2.6, height: 0.12, alongLongAxis: false, stretched: true, tilt: -0.5),
            tint: 0x2B3A55
        ),
        "battery-room": Look(.building(meshes: outbuildingMeshes, height: 2.6), tint: 0x8894A0),
        "inverter-room": Look(.building(meshes: outbuildingMeshes, height: 2.4), tint: 0x9AA6B2),
        "generator": Look(.single(model: "works/machine-fortified", fit: .footprint(height: 2.0))),

        // Ground ---------------------------------------------------------
        "patio": Look(
            .surface(colour: 0xCFC2A4, height: 0.12),
            props: [
                Prop("yard/bench", fit: .spanning(1.8), direction: (-0.5, 0.0)),
                Prop("yard/lightpost-single", fit: .standing(height: 3.0), direction: (0.62, 0.62)),
            ]
        ),
    ]
}
