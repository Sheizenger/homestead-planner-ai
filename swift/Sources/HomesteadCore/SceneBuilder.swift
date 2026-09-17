import Foundation
import HomesteadEngine

/// Deterministic scatter. `Double.random` would re-roll every rebuild and make
/// the orchard shuffle itself whenever anything else on the plot changed.
enum SceneNoise {
    static func value(_ seed: String, _ index: Int, _ salt: Int = 0) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3 }
        hash = (hash ^ UInt64(bitPattern: Int64(index))) &* 0x1000_0000_01b3
        hash = (hash ^ UInt64(bitPattern: Int64(salt))) &* 0x1000_0000_01b3
        hash ^= hash >> 33
        return Double(hash % 100_000) / 100_000
    }

    static func jitter(_ seed: String, _ index: Int, _ salt: Int, _ amount: Double) -> Double {
        (value(seed, index, salt) - 0.5) * 2 * amount
    }
}

/// An extruded polygon: the ground, a patio, a path, the surface of a pool.
///
/// Not everything is a mesh, and pretending otherwise is how a patio ends up
/// being a market stall stretched to forty square metres. Nothing in any kit
/// is the shape of one particular plot, so these are built rather than
/// loaded — which the renderer can do from a polygon in three lines.
public struct SceneSlab: Identifiable, Equatable, Sendable {
    public var id: String
    /// In the engine's plan coordinates; the renderer maps them across.
    public var polygon: [Point]
    /// Height of the top face, metres above the plot's grade.
    public var top: Double
    /// How far down it goes. Zero draws a flat face with no sides.
    public var thickness: Double
    public var colour: Int
    public var objectId: String?

    public init(
        id: String,
        polygon: [Point],
        top: Double,
        thickness: Double,
        colour: Int,
        objectId: String? = nil
    ) {
        self.id = id
        self.polygon = polygon
        self.top = top
        self.thickness = thickness
        self.colour = colour
        self.objectId = objectId
    }
}

/// A volume built rather than loaded: a glasshouse, the water in a pool, a
/// cold store cut into a bank.
///
/// Three kinds of object defeat both of the other primitives. A slab is flat,
/// so a greenhouse drawn as one is a pane of glass lying on the grass — which
/// is exactly what the first pass produced. And no kit contains a greenhouse,
/// a swimming pool or a root cellar, so there is no mesh to stretch either.
/// A box with an optional pitched top covers all of them, and the renderer
/// builds it from the footprint in a few lines.
public struct SceneSolid: Identifiable, Equatable, Sendable {
    public var id: String
    public var polygon: [Point]
    /// Height of the eaves above grade; negative sinks it.
    public var base: Double
    public var wallHeight: Double
    /// Extra height at the ridge. Zero is a flat-topped box.
    public var ridgeRise: Double
    /// True when the ridge runs along the footprint's longer axis, which is
    /// what a real roof does.
    public var ridgeAlongLongAxis: Bool
    public var colour: Int
    /// 1 is opaque. Glass and water are not.
    public var opacity: Double
    public var objectId: String?

    public init(
        id: String, polygon: [Point], base: Double = 0, wallHeight: Double,
        ridgeRise: Double = 0, ridgeAlongLongAxis: Bool = true,
        colour: Int, opacity: Double = 1, objectId: String? = nil
    ) {
        self.id = id
        self.polygon = polygon
        self.base = base
        self.wallHeight = wallHeight
        self.ridgeRise = ridgeRise
        self.ridgeAlongLongAxis = ridgeAlongLongAxis
        self.colour = colour
        self.opacity = opacity
        self.objectId = objectId
    }
}

/// Everything the renderer needs, and nothing it has to work out for itself.
public struct Scene3D: Equatable, Sendable {
    public var meshes: [SceneNode]
    public var slabs: [SceneSlab]
    public var solids: [SceneSolid]

    public init(meshes: [SceneNode] = [], slabs: [SceneSlab] = [], solids: [SceneSolid] = []) {
        self.meshes = meshes
        self.slabs = slabs
        self.solids = solids
    }

    public var isEmpty: Bool { meshes.isEmpty && slabs.isEmpty && solids.isEmpty }
}

/// Turns a plan into a scene.
///
/// All of it is pure, and all of it runs here — which is the point. The app
/// target cannot be compiled on Linux, let alone rendered, so every question
/// that can be decided without a GPU is decided in this file and pinned by
/// tests: what mesh, how big, facing where, standing on what. What is left
/// for the renderer is walking a list.
public enum SceneBuilder {
    public static let grassColour = 0x7FA650
    public static let soilColour = 0x6B5540
    public static let pathColour = 0xC9B48C
    /// Hardstanding: darker and coarser than a garden path, because a car
    /// drives on it.
    public static let drivewayColour = 0x8E8B85

    /// What height each kind of flat surface sits at.
    ///
    /// Flat things laid on flat things are where a depth buffer has nothing
    /// to go on: two surfaces within a millimetre of each other have no
    /// depth order, the renderer picks per pixel, and the seam crawls as the
    /// camera turns. Four centimetres apart is invisible at plan scale and
    /// far more than any depth buffer needs, so the order is stated once here
    /// rather than guessed at each call site.
    public enum Ground {
        public static let lawn = 0.0
        public static let worn = 0.02        // a paddock, an apiary
        public static let path = 0.06
        public static let hardstanding = 0.10
        public static let paving = 0.15      // a patio
        public static let coping = 0.20      // the rim of a pool
    }
    /// How thick the block of land is. The plot is a solid thing seen from
    /// above, not a sheet of paper.
    public static let groundThickness = 1.6

    public static func build(
        plot: Plot,
        variant: Variant,
        metrics: [String: ModelBounds] = ModelMetrics.all
    ) -> Scene3D {
        var scene = Scene3D()
        ground(plot, into: &scene)
        water(plot, into: &scene)
        paths(variant, into: &scene)

        let footprints = variant.objects.map { ($0.id, Massing3D.footprint(of: $0)) }
        let gate = gatePoint(of: plot, variant: variant)
        for object in variant.objects {
            place(
                object, into: &scene,
                avoiding: footprints.filter { $0.0 != object.id }.map(\.1),
                gate: gate,
                base: baseElevation(of: object, among: variant.objects, metrics: metrics),
                metrics: metrics
            )
        }

        // Props go in a pass of their own, after every building is down,
        // because each has to keep clear of what is already there — including
        // other objects' props. Placed per object, the garage's car and the
        // woodshed's log pile were both pushed out of their own buildings and
        // onto the same square metre of grass.
        var taken: [(centre: Point, radius: Double)] = []
        for object in variant.objects {
            let look = SceneCatalog.look(for: object)
            guard !look.props.isEmpty else { continue }
            scene.meshes += props(
                object,
                look: look,
                avoiding: footprints.filter { $0.0 != object.id }.map(\.1),
                clearOf: &taken,
                inside: propsStandOnTheirObject(look),
                metrics: metrics
            )
        }
        fences(variant, plot, into: &scene, metrics: metrics)
        undergrowth(plot, variant, into: &scene, metrics: metrics)
        return scene
    }

    // MARK: - The rest of the land

    /// What grows where nothing was built.
    ///
    /// A plot with eighteen objects on it and bare green everywhere else
    /// reads as a model of a site rather than a site. The references are
    /// dense: there is always something in the middle distance. This is that
    /// — tufts, the odd rock, a tree well away from anything — scattered on a
    /// jittered grid so it does not read as a pattern, seeded off the plan so
    /// it does not crawl when anything else changes.
    static let tuftMeshes = ["survival/grass", "survival/grass-large", "survival/patch-grass"]
    static let rockMeshes = ["town/rock-small", "town/rock-wide", "survival/rock-a", "yard/rocks"]
    static let wildTreeMeshes = ["forest/tree", "survival/tree", "survival/tree-tall", "yard/pine"]
    /// Grid pitch for the scatter, metres.
    static let undergrowthSpacing = 4.2
    /// How far a wild tree keeps from anything built. Close enough and it is
    /// not wild, it is landscaping — and it hides the thing behind it.
    static let treeClearance = 7.0

    static func undergrowth(
        _ plot: Plot,
        _ variant: Variant,
        into scene: inout Scene3D,
        metrics: [String: ModelBounds]
    ) {
        guard let bounds = plot.bounds, plot.boundary.count > 2 else { return }
        let land = dryLand(of: plot)
        let footprints = variant.objects.map { (Massing3D.footprint(of: $0), $0.transform) }
        let routes = variant.paths.flatMap(\.points) + variant.fences.flatMap(\.points)

        var index = 0
        var y = bounds.minY + undergrowthSpacing / 2
        while y < bounds.maxY {
            var x = bounds.minX + undergrowthSpacing / 2
            while x < bounds.maxX {
                index += 1
                let point = Point(
                    x: x + SceneNoise.jitter("wild", index, 1, undergrowthSpacing * 0.42),
                    y: y + SceneNoise.jitter("wild", index, 2, undergrowthSpacing * 0.42)
                )
                x += undergrowthSpacing
                guard Polygon.contains(point, polygon: land) else { continue }
                // Nothing grows through a building, a bed or a paddock, and
                // nothing grows in the middle of a path.
                //
                // `Polygon.clearance` takes two polygons and answers
                // `.infinity` for anything with fewer than two points, so
                // asking it about a single point excluded nothing at all and
                // let wild trees grow through the barn.
                let nearestBuilt = footprints.map { footprint, _ -> Double in
                    if Polygon.contains(point, polygon: footprint) { return 0 }
                    return Polygon.distanceToBoundary(point, polygon: footprint) ?? .infinity
                }.min() ?? .infinity
                guard nearestBuilt > 0.7 else { continue }
                guard routes.allSatisfy({ distance($0, point) > 1.2 }) else { continue }

                let roll = SceneNoise.value("wild", index, 3)
                let model: String
                let fit: ModelFit
                if roll < 0.10, nearestBuilt > treeClearance {
                    model = wildTreeMeshes[index % wildTreeMeshes.count]
                    fit = .standing(height: 4.0 + SceneNoise.value("wild", index, 4) * 2.4)
                } else if roll < 0.20 {
                    model = rockMeshes[index % rockMeshes.count]
                    fit = .spanning(0.6 + SceneNoise.value("wild", index, 5) * 0.9)
                } else if roll < 0.78 {
                    model = tuftMeshes[index % tuftMeshes.count]
                    fit = .spanning(0.7 + SceneNoise.value("wild", index, 6) * 0.8)
                } else {
                    continue
                }
                if let node = ModelPlacement.node(
                    id: "wild-\(index)",
                    model: model,
                    centre: point,
                    yaw: SceneNoise.value("wild", index, 7) * 2 * .pi,
                    fit: fit,
                    metrics: metrics
                ) {
                    scene.meshes.append(node)
                }
            }
            y += undergrowthSpacing
        }
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    // MARK: - The site

    /// The block of land, with the waterfront taken out of it.
    ///
    /// Cutting the water out matters more than it sounds. Leaving the ground
    /// whole and laying the water over it works on paper and fails in a
    /// renderer with a depth buffer: the water surface sits *below* grade, so
    /// the lawn is in front of it and the river simply does not appear. It did
    /// not appear.
    static func ground(_ plot: Plot, into scene: inout Scene3D) {
        guard plot.boundary.count > 2 else { return }
        scene.slabs.append(SceneSlab(
            id: "ground",
            polygon: dryLand(of: plot),
            top: 0,
            thickness: groundThickness,
            colour: grassColour
        ))
    }

    /// The plot with its waterfront strip removed. The strip is always along
    /// one edge, so what is left is the boundary clipped to a rectangle —
    /// which works for a notched or L-shaped plot as well as a square one.
    static func dryLand(of plot: Plot) -> [Point] {
        guard let waterfront = plot.waterfront,
              let bounds = plot.bounds,
              let strip = WaterfrontModel.bounds(of: plot) else { return plot.boundary }
        let land: Rect
        switch waterfront.edge {
        case .north: land = Rect(minX: bounds.minX, minY: strip.maxY, maxX: bounds.maxX, maxY: bounds.maxY)
        case .south: land = Rect(minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: strip.minY)
        case .west: land = Rect(minX: strip.maxX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY)
        case .east: land = Rect(minX: bounds.minX, minY: bounds.minY, maxX: strip.minX, maxY: bounds.maxY)
        }
        guard land.width > 0, land.height > 0 else { return plot.boundary }
        let clipped = Polygon.clip(plot.boundary, to: land)
        return clipped.count >= 3 ? clipped : plot.boundary
    }

    static func water(_ plot: Plot, into scene: inout Scene3D) {
        guard let waterfront = plot.waterfront,
              let strip = WaterfrontModel.bounds(of: plot),
              let shore = WaterfrontModel.shoreline(of: plot), shore.count > 2 else { return }
        let look = WaterPalette.of(waterfront.type)

        // The bank is the part of the planning strip the water does not reach.
        // Only the dry part. A bank across the whole strip is an opaque lid
        // over water that sits below it.
        if let bank = WaterfrontModel.bank(of: plot), bank.count > 2 {
            scene.slabs.append(SceneSlab(
                id: "waterfront-bank",
                polygon: bank,
                top: 0,
                thickness: groundThickness,
                colour: look.bank
            ))
        }
        _ = strip
        scene.slabs.append(SceneSlab(
            id: "waterfront",
            polygon: shore,
            top: -look.depth,
            thickness: groundThickness - look.depth,
            colour: look.deep
        ))
    }

    static func paths(_ variant: Variant, into scene: inout Scene3D) {
        for (index, path) in variant.paths.enumerated() {
            let half = max(0.3, path.widthM / 2)
            for step in 0..<max(0, path.points.count - 1) {
                let a = path.points[step]
                let b = path.points[step + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 1e-6 else { continue }
                // Perpendicular, and overlapped a little at each end so the
                // corners of a dog-leg do not show daylight between segments.
                let nx = -dy / length * half
                let ny = dx / length * half
                let ex = dx / length * half * 0.9
                let ey = dy / length * half * 0.9
                scene.slabs.append(SceneSlab(
                    id: "path-\(index)-\(step)",
                    polygon: [
                        Point(x: a.x + nx - ex, y: a.y + ny - ey),
                        Point(x: b.x + nx + ex, y: b.y + ny + ey),
                        Point(x: b.x - nx + ex, y: b.y - ny + ey),
                        Point(x: a.x - nx - ex, y: a.y - ny - ey),
                    ],
                    top: Ground.path,
                    thickness: 0,
                    colour: pathColour
                ))
            }
        }
    }

    // MARK: - Objects

    static func place(
        _ object: PlanObject,
        into scene: inout Scene3D,
        avoiding neighbours: [[Point]] = [],
        gate: Point? = nil,
        base: Double = 0,
        metrics: [String: ModelBounds]
    ) {
        let look = SceneCatalog.look(for: object)
        let transform = object.transform
        if object.typeId == "garage", let gate {
            scene.slabs.append(driveway(for: object, towards: gate))
        }
        let footprint = Size(width: transform.width, height: transform.height)
        let yaw = sceneYaw(fromEngineDegrees: transform.rotationDeg)

        switch look.massing {
        case let .building(meshes, height):
            scene.meshes += building(
                object, meshes: meshes, height: height, tint: look.tint, metrics: metrics
            )

        case let .single(model, fit):
            if let node = ModelPlacement.node(
                id: object.id, model: model, centre: transform.center, base: base, yaw: yaw,
                fit: fit, footprint: footprint, objectId: object.id, tint: look.tint, metrics: metrics
            ) {
                scene.meshes.append(node)
            }

        case let .scatter(models, density, height):
            scene.meshes += scatter(
                object, models: models, density: density, height: height,
                tint: look.tint, metrics: metrics
            )

        case let .rows(model, spacing, height, alongLongAxis, stretched, tilt):
            scene.meshes += rows(
                object, model: model, spacing: spacing, height: height,
                alongLongAxis: alongLongAxis, stretched: stretched, tilt: tilt,
                base: base, tint: look.tint, metrics: metrics
            )

        case let .volume(colour, wallHeight, ridgeRise, opacity):
            let footprintPolygon = Massing3D.footprint(of: object)
            scene.solids.append(SceneSolid(
                id: object.id,
                polygon: footprintPolygon,
                wallHeight: wallHeight,
                ridgeRise: ridgeRise,
                ridgeAlongLongAxis: true,
                colour: colour,
                opacity: opacity,
                objectId: object.id
            ))

        case let .surface(colour, height):
            scene.slabs.append(SceneSlab(
                id: object.id, polygon: Massing3D.footprint(of: object),
                top: height, thickness: height > 0.02 ? height : 0,
                colour: colour, objectId: object.id
            ))

        case let .sunken(colour, depth):
            // The rim is a frame around the water, not a lid over it. Drawn as
            // the whole footprint it sat two-tenths of a metre above a pool
            // that is sunk below grade, so it covered it completely and a pool
            // rendered as a beige slab with no water in it.
            let outer = Massing3D.footprint(of: object)
            let inner = inset(outer, by: 0.5)
            for corner in outer.indices {
                let next = (corner + 1) % outer.count
                scene.slabs.append(SceneSlab(
                    id: object.id + "-coping-\(corner)",
                    polygon: [outer[corner], outer[next], inner[next], inner[corner]],
                    top: Ground.coping, thickness: Ground.coping,
                    colour: 0xD8D2C4, objectId: object.id
                ))
            }
            // Held inside the rim rather than sunk below grade. The ground is
            // a solid block and an extruded polygon cannot cut a hole in it —
            // the same limitation the river is drawn around — so water put
            // below zero is water inside the block, and the pool showed lawn.
            // Filled to just under the coping, the rim carries the depth.
            //
            // `depth` is what the pool is, not what can be drawn of it. The
            // body is capped just below grade: any more hangs down inside the
            // block of land where it cannot be seen from above, and shows as
            // a slab of blue down the cut face wherever the land is cut.
            scene.slabs.append(SceneSlab(
                id: object.id, polygon: inner,
                top: Ground.coping - 0.05, thickness: min(depth, Ground.coping + 0.1),
                colour: colour, objectId: object.id
            ))
        }

    }

    /// Props of a *building* stand beside it; props of a *place* stand on it.
    /// Pushing everything outside put the paddock's grass and the patio's
    /// bench out on the lawn.
    static func propsStandOnTheirObject(_ look: SceneCatalog.Look) -> Bool {
        switch look.massing {
        case .surface, .sunken: return true
        default: return false
        }
    }

    /// A building at its real dimensions.
    ///
    /// No mesh in any kit is 12 by 10 metres, so one has to be stretched to
    /// fit — and a house stretched to the wrong proportions looks exactly like
    /// a house stretched to the wrong proportions. Two things keep it honest.
    /// The mesh is chosen for how close its own proportions already are, in
    /// either orientation; and where nothing comes close, the footprint is
    /// split into bays along its long axis and each bay gets a mesh, which is
    /// what a long building actually is.
    static func building(
        _ object: PlanObject,
        meshes: [String],
        height: Double,
        tint: Int?,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let width = transform.width
        let depth = transform.height
        guard width > 0, depth > 0, !meshes.isEmpty else { return [] }

        guard let choice = chooseBuilding(meshes: meshes, width: width, depth: depth, seed: object.id, metrics: metrics)
        else { return [] }

        // Height follows the mesh, it is not dictated to it.
        //
        // Forcing the catalog's height regardless of how far the footprint
        // stretched the mesh sideways is what turned a 12 x 10 house into a
        // windowless block: nine times as wide as the mesh, seven times as
        // tall, and nothing about it a house any more. Scaling height by the
        // geometric mean of the two horizontal stretches keeps the mesh's own
        // proportions; the catalog height then only says roughly how big a
        // thing of this kind is, and clamps the result to within half again
        // of it so a wide footprint cannot raise a tower.
        guard let chosenBounds = metrics[choice.model] else { return [] }
        let proportional = proportionalHeight(
            bounds: chosenBounds, choice: choice, width: width, depth: depth
        )
        let height = min(max(proportional, height * 0.7), height * 1.45)

        let baseYaw = sceneYaw(fromEngineDegrees: transform.rotationDeg)
        let yaw = baseYaw + (choice.turned ? .pi / 2 : 0)
        // Bays run along whichever plan axis is longer.
        let alongX = width >= depth
        let bayLength = (alongX ? width : depth) / Double(choice.bays)
        let bayFootprint = alongX
            ? Size(width: bayLength, height: depth)
            : Size(width: width, height: bayLength)
        // A turned mesh has its own axes swapped, so the footprint it is
        // asked to fill has to be swapped with it.
        let meshFootprint = choice.turned
            ? Size(width: bayFootprint.height, height: bayFootprint.width)
            : bayFootprint

        var nodes: [SceneNode] = []
        for bay in 0..<choice.bays {
            let offset = (Double(bay) + 0.5) * bayLength - (alongX ? width : depth) / 2
            let local = alongX ? Point(x: offset, y: 0) : Point(x: 0, y: offset)
            let centre = rotate(local, by: transform.rotationDeg * .pi / 180, around: transform.center)
            if let node = ModelPlacement.node(
                id: "\(object.id)-bay\(bay)",
                model: choice.model,
                centre: centre,
                yaw: yaw,
                fit: .footprint(height: height),
                footprint: meshFootprint,
                objectId: object.id,
                tint: tint,
                metrics: metrics
            ) {
                nodes.append(node)
            }
        }
        return nodes
    }

    /// What the chosen mesh would stand at if it were scaled evenly.
    static func proportionalHeight(
        bounds: ModelBounds, choice: BuildingChoice, width: Double, depth: Double
    ) -> Double {
        let alongX = width >= depth
        let bayWidth = alongX ? width / Double(choice.bays) : width
        let bayDepth = alongX ? depth : depth / Double(choice.bays)
        let meshWidth = choice.turned ? bounds.depth : bounds.width
        let meshDepth = choice.turned ? bounds.width : bounds.depth
        guard meshWidth > 1e-9, meshDepth > 1e-9, bounds.height > 1e-9 else { return bounds.height }
        return bounds.height * ((bayWidth / meshWidth) * (bayDepth / meshDepth)).squareRoot()
    }

    struct BuildingChoice: Equatable {
        var model: String
        var turned: Bool
        var bays: Int
        var distortion: Double
    }

    /// How much worse than the best available fit a building may be, in
    /// exchange for not being the same building as its neighbour.
    ///
    /// Picking the closest-fitting mesh every time is the obvious rule and it
    /// is wrong: in a plan with a shed, a coop, a goat shelter, a banya and a
    /// smokehouse, all five footprints are small and roughly square, so all
    /// five choose the same mesh and the plot grows five identical huts. That
    /// is the "дома очень однообразные" complaint, arrived at from a new
    /// direction. Variety has to be a goal rather than a tie-break, so any fit
    /// within a quarter of the best is fair game and the object's own id picks
    /// among them.
    public static let fitTolerance = 1.25

    /// The ways a footprint can be filled from a set of meshes, best first.
    ///
    /// Distortion is how far the two horizontal stretch factors differ: 1.0 is
    /// a mesh scaled evenly, 2.0 is one twice as stretched one way as the
    /// other.
    static func buildingOptions(
        meshes: [String],
        width: Double,
        depth: Double,
        maximumBays: Int = 4,
        metrics: [String: ModelBounds] = ModelMetrics.all
    ) -> [BuildingChoice] {
        let alongX = width >= depth
        var options: [BuildingChoice] = []
        for model in meshes {
            guard let bounds = metrics[model], bounds.width > 0, bounds.depth > 0 else { continue }
            for turned in [false, true] {
                let meshWidth = turned ? bounds.depth : bounds.width
                let meshDepth = turned ? bounds.width : bounds.depth
                for bays in 1...maximumBays {
                    let bayWidth = alongX ? width / Double(bays) : width
                    let bayDepth = alongX ? depth : depth / Double(bays)
                    let stretchX = bayWidth / meshWidth
                    let stretchZ = bayDepth / meshDepth
                    guard stretchX > 0, stretchZ > 0 else { continue }
                    // Extra pieces are a cost of their own: a two-bay fit has
                    // to be meaningfully better than a one-bay fit to be worth
                    // cutting the building in half.
                    let distortion = max(stretchX / stretchZ, stretchZ / stretchX)
                        + Double(bays - 1) * 0.08
                    options.append(BuildingChoice(
                        model: model, turned: turned, bays: bays, distortion: distortion
                    ))
                }
            }
        }
        return options.sorted {
            $0.distortion == $1.distortion
                ? ($0.model, $0.bays, $0.turned ? 1 : 0) < ($1.model, $1.bays, $1.turned ? 1 : 0)
                : $0.distortion < $1.distortion
        }
    }

    static func chooseBuilding(
        meshes: [String],
        width: Double,
        depth: Double,
        seed: String,
        maximumBays: Int = 4,
        metrics: [String: ModelBounds] = ModelMetrics.all
    ) -> BuildingChoice? {
        let options = buildingOptions(
            meshes: meshes, width: width, depth: depth, maximumBays: maximumBays, metrics: metrics
        )
        guard let best = options.first else { return nil }
        // Every option that is not noticeably worse than the best, then one of
        // them chosen by the object's own id — so the same brief always draws
        // the same plot, and two sheds side by side are two sheds.
        let acceptable = options.filter { $0.distortion <= best.distortion * fitTolerance }
        let pick = Int(SceneNoise.value(seed, acceptable.count, 11) * Double(acceptable.count))
        return acceptable[min(pick, acceptable.count - 1)]
    }

    static func scatter(
        _ object: PlanObject,
        models: [String],
        density: Double,
        height: Double,
        tint: Int?,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let radians = transform.rotationDeg * .pi / 180
        // `density` is trees per square metre; a grid at that density is what
        // an orchard is. Scattered at random it reads as scrub — which is the
        // right answer for rough ground and the wrong one for planting.
        let pitch = max(3.0, (1 / max(density, 0.001)).squareRoot())
        // Rounded rather than floored: a 14 m side at a 5 m pitch is three
        // trees, not two, and flooring both sides of a small orchard loses
        // half of it.
        let columns = max(1, Int((transform.width / pitch).rounded()))
        let rows = max(1, Int((transform.height / pitch).rounded()))
        let wanted = min(90, columns * rows)

        var nodes: [SceneNode] = []
        for index in 0..<wanted {
            let model = models[index % models.count]
            let column = index % columns
            let row = index / columns
            let local = Point(
                x: (Double(column) + 0.5) * transform.width / Double(columns) - transform.width / 2
                    + SceneNoise.jitter(object.id, index, 1, pitch * 0.14),
                y: (Double(row) + 0.5) * transform.height / Double(rows) - transform.height / 2
                    + SceneNoise.jitter(object.id, index, 2, pitch * 0.14)
            )
            let scaled = height * (0.82 + SceneNoise.value(object.id, index, 3) * 0.36)
            if let node = ModelPlacement.node(
                id: "\(object.id)-\(index)",
                model: model,
                centre: rotate(local, by: radians, around: transform.center),
                yaw: SceneNoise.value(object.id, index, 4) * 2 * .pi,
                fit: .standing(height: scaled),
                objectId: object.id,
                tint: tint,
                metrics: metrics
            ) {
                nodes.append(node)
            }
        }
        return nodes
    }

    /// The most plants a single field is allowed to draw.
    ///
    /// A grain field at a realistic row and plant spacing is thousands of
    /// meshes, and a plan has four or five fields. The cap is what keeps a
    /// scene at a few hundred nodes rather than a few thousand; spacing opens
    /// out to meet it, so a big field is a sparser field rather than a
    /// truncated one.
    public static let plantsPerField = 150

    /// Crops, vines, beds and panels.
    ///
    /// One stretched mesh per row was the first attempt and it is the exact
    /// mistake `ModelFit` warns about: `.footprint` is for modular pieces
    /// that are made to stretch, and a tuft of grass pulled out to twenty
    /// metres is a twenty-metre blade of grass. It looked like one. Plants
    /// repeat at their own size instead, and only a panel — which really is
    /// a flat rectangular thing — still stretches.
    static func rows(
        _ object: PlanObject,
        model: String,
        spacing: Double,
        height: Double,
        alongLongAxis: Bool,
        stretched: Bool,
        tilt: Double,
        base: Double,
        tint: Int?,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let longIsX = (transform.width >= transform.height) == alongLongAxis
        let rowLength = longIsX ? transform.width : transform.height
        let across = longIsX ? transform.height : transform.width
        guard rowLength > 0.5, across > 0.5, spacing > 0.1 else { return [] }

        let radians = transform.rotationDeg * .pi / 180
        let yaw = sceneYaw(fromEngineDegrees: transform.rotationDeg)
        // Flat on a roof, leaning on the ground.
        let tilt = base > 0.01 ? 0 : tilt

        if stretched {
            guard let bounds = metrics[model] else { return [] }
            let count = max(1, min(40, Int((across / spacing).rounded(.down))))
            let step = across / Double(count)
            // A modular row piece is repeated along the row at close to its
            // own length, the way a fence panel is — not stretched to the
            // whole of it. A hedge pulled out to nine metres drags its stone
            // base out with it, and what you get is a long white plinth.
            let natural = max(0.5, bounds.depth / max(bounds.height, 1e-6) * height)
            let pieces = max(1, Int((rowLength * 0.94 / natural).rounded()))
            let pieceLength = rowLength * 0.94 / Double(pieces)
            var nodes: [SceneNode] = []
            for row in 0..<count {
                let offset = (Double(row) + 0.5) * step - across / 2
                for piece in 0..<pieces {
                    let alongOffset = (Double(piece) + 0.5) * pieceLength - rowLength * 0.94 / 2
                let local = longIsX
                    ? Point(x: alongOffset, y: offset)
                    : Point(x: offset, y: alongOffset)
                let footprint = longIsX
                    ? Size(width: pieceLength, height: min(step * 0.62, spacing * 0.62))
                    : Size(width: min(step * 0.62, spacing * 0.62), height: pieceLength)
                if var node = ModelPlacement.node(
                    id: "\(object.id)-row\(row)-\(piece)",
                    model: model,
                    centre: rotate(local, by: radians, around: transform.center),
                    base: base,
                    yaw: yaw,
                    pitch: tilt,
                    fit: .footprint(height: height),
                    footprint: footprint,
                    objectId: object.id,
                    tint: tint,
                    metrics: metrics
                ) {
                    // Tilting about the node's own origin would swing half the
                    // panel through whatever it stands on, so a leaning array
                    // stands on legs. On a roof it does not lean at all —
                    // panels follow the pitch there, and a tilt on top of a
                    // seat computed from the roof's own profile lifted them
                    // clean over the ridge.
                    if tilt != 0 {
                        node.position.y += abs(sin(tilt)) * footprint.height / 2 + 0.5
                    }
                    nodes.append(node)
                }
                }
            }
            return nodes
        }

        // Rows across the bed, plants along each row, both opened out
        // together until the whole field fits under the cap.
        var rowStep = spacing
        var plantStep = spacing * 0.82
        var rowCount = max(1, Int((across / rowStep).rounded(.down)))
        var plantCount = max(1, Int((rowLength / plantStep).rounded(.down)))
        while rowCount * plantCount > plantsPerField {
            rowStep *= 1.18
            plantStep *= 1.18
            rowCount = max(1, Int((across / rowStep).rounded(.down)))
            plantCount = max(1, Int((rowLength / plantStep).rounded(.down)))
        }
        let rowSpan = across / Double(rowCount)
        let plantSpan = rowLength / Double(plantCount)

        var nodes: [SceneNode] = []
        for row in 0..<rowCount {
            let acrossOffset = (Double(row) + 0.5) * rowSpan - across / 2
            for plant in 0..<plantCount {
                let alongOffset = (Double(plant) + 0.5) * plantSpan - rowLength / 2
                let index = row * plantCount + plant
                // Jittered along the row but not across it: a row that
                // wanders sideways stops being a row.
                let wobble = SceneNoise.jitter(object.id, index, 1, plantSpan * 0.18)
                let local = longIsX
                    ? Point(x: alongOffset + wobble, y: acrossOffset)
                    : Point(x: acrossOffset, y: alongOffset + wobble)
                let scaled = height * (0.84 + SceneNoise.value(object.id, index, 2) * 0.32)
                if let node = ModelPlacement.node(
                    id: "\(object.id)-\(row)-\(plant)",
                    model: model,
                    centre: rotate(local, by: radians, around: transform.center),
                    base: base,
                    yaw: yaw + SceneNoise.jitter(object.id, index, 3, 0.5),
                    fit: .standing(height: scaled),
                    objectId: object.id,
                    tint: tint,
                    metrics: metrics
                ) {
                    nodes.append(node)
                }
            }
        }
        return nodes
    }

    /// How far a prop stands clear of the thing it belongs to.
    public static let propClearance = 0.6

    /// Props, standing beside their object rather than inside it.
    ///
    /// The old rule read the offset as a fraction of the half-extent, so any
    /// value under 1.0 put the prop inside the footprint: a tractor at 0.7 of
    /// a ten-metre barn stood three and a half metres from its centre, which
    /// is indoors. This walks out along the given direction to where the ray
    /// leaves the footprint, then keeps going by the prop's own half-size, so
    /// what is placed is beside the building whatever size either of them is.
    /// The directions a prop will try, in order, before giving up: the one it
    /// asked for, then further and further round the building.
    static let propTurns: [Double] = [0, .pi / 4, -.pi / 4, .pi / 2, -.pi / 2, .pi]

    static func props(
        _ object: PlanObject,
        look: SceneCatalog.Look,
        avoiding neighbours: [[Point]] = [],
        clearOf taken: inout [(centre: Point, radius: Double)],
        inside standsOn: Bool = false,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let radians = transform.rotationDeg * .pi / 180
        let halfWidth = transform.width / 2
        let halfDepth = transform.height / 2

        var nodes: [SceneNode] = []
        for (index, prop) in look.props.enumerated() {
            guard let bounds = metrics[prop.model] else { continue }
            let scale = ModelPlacement.scale(
                for: prop.fit, bounds: bounds,
                footprint: Size(width: transform.width, height: transform.height)
            )
            let propHalf = max(bounds.width * scale.x, bounds.depth * scale.z) / 2

            let length = (prop.direction.x * prop.direction.x + prop.direction.y * prop.direction.y).squareRoot()
            let asked = length > 1e-6
                ? (x: prop.direction.x / length, y: prop.direction.y / length)
                : (x: 1.0, y: 0.0)

            /// Where the ray from the centre leaves the footprint.
            func exit(_ unit: (x: Double, y: Double)) -> Double {
                min(
                    abs(unit.x) > 1e-6 ? halfWidth / abs(unit.x) : .infinity,
                    abs(unit.y) > 1e-6 ? halfDepth / abs(unit.y) : .infinity
                )
            }

            /// Clear of the building is not the same as clear. Pushing every
            /// prop out of its own footprint moved them all onto the
            /// neighbours instead — a tractor out of the barn and into the
            /// house. A prop tries the side it was given, then walks round
            /// the building until it finds one that is free, and if none is,
            /// it is not drawn: a plot with nowhere for the cart does not
            /// need one drawn through a wall.
            var unit = asked
            var reach = 0.0
            let belongsInside = prop.inside || standsOn
            var placed = belongsInside
            if !belongsInside {
                for turn in propTurns {
                    let cosine = cos(turn)
                    let sine = sin(turn)
                    let candidate = (x: asked.x * cosine - asked.y * sine, y: asked.x * sine + asked.y * cosine)
                    // Not `distance` — that is the function two lines below.
                    let outward = exit(candidate) + propHalf + propClearance
                    let local = Point(x: candidate.x * outward, y: candidate.y * outward)
                    let world = rotate(local, by: radians, around: transform.center)
                    let clearOfBuildings = neighbours.allSatisfy { footprint in
                        if Polygon.contains(world, polygon: footprint) { return false }
                        return (Polygon.distanceToBoundary(world, polygon: footprint) ?? .infinity) > propHalf
                    }
                    let clearOfProps = taken.allSatisfy {
                        distance(world, $0.centre) > propHalf + $0.radius
                    }
                    let clear = clearOfBuildings && clearOfProps
                    if clear {
                        unit = candidate
                        reach = outward
                        placed = true
                        break
                    }
                }
            }
            guard placed else { continue }

            // Several of a thing stand in a line along the wall, spaced by
            // their own size — the old fixed 1.1 m piled 1.6 m hay bales into
            // each other.
            let along = (x: -unit.y, y: unit.x)
            let step = propHalf * 2 + 0.35
            for copy in 0..<prop.count {
                let spread = prop.count > 1 ? (Double(copy) - Double(prop.count - 1) / 2) * step : 0
                let jitter = belongsInside ? 0.25 : 0.14
                let local = Point(
                    x: unit.x * reach + along.x * spread
                        + SceneNoise.jitter(object.id, index * 10 + copy, 5, jitter),
                    y: unit.y * reach + along.y * spread
                        + SceneNoise.jitter(object.id, index * 10 + copy, 6, jitter)
                )
                if let node = ModelPlacement.node(
                    id: "\(object.id)-\(belongsInside ? "inprop" : "prop")\(index)-\(copy)",
                    model: prop.model,
                    centre: rotate(local, by: radians, around: transform.center),
                    yaw: sceneYaw(fromEngineDegrees: transform.rotationDeg) + prop.yaw
                        + SceneNoise.jitter(object.id, index * 10 + copy, 7, 0.2),
                    fit: prop.fit,
                    footprint: Size(width: transform.width, height: transform.height),
                    objectId: object.id,
                    metrics: metrics
                ) {
                    nodes.append(node)
                    if let centre = ModelPlacement.footprintCentre(of: node, metrics: metrics) {
                        taken.append((centre: centre, radius: propHalf))
                    }
                }
            }
        }
        return nodes
    }

    /// A little clear of the roof, so it reads as mounted on it rather than
    /// flush with it.
    static let roofLift = 0.15

    /// The ground a thing stands on.
    ///
    /// Almost always zero. A solar array is the exception: the placer puts it
    /// *inside* the house's footprint on purpose, because it goes on the
    /// roof, and a scene builder that does not know this lays it on the lawn
    /// under the house — which is one building passing through another, and
    /// the first thing anyone notices.
    static func baseElevation(
        of object: PlanObject,
        among objects: [PlanObject],
        metrics: [String: ModelBounds]
    ) -> Double {
        guard object.metadata["roofMounted"]?.boolValue == true else { return 0 }
        let host = objects.first { other in
            other.id != object.id
                && other.metadata["roofMounted"]?.boolValue != true
                && Polygon.contains(object.transform.center, polygon: Massing3D.footprint(of: other))
        }
        guard let host,
              let height = buildingHeight(of: host, metrics: metrics),
              let mesh = hostMesh(of: host, metrics: metrics) else { return 0 }

        // How high the host stands over the patch of it being built on.
        //
        // Not a fraction of its height — that is the question two earlier
        // attempts answered, and it is the wrong one. A cross-section is
        // nearly full at a third of a house's height, but that is the first
        // floor and an array seated there is indoors; it is nearly empty near
        // the top, and an array seated there floats above the ridge.
        // `ModelBounds.top` says how high the roof is *over this spot*, which
        // is what standing on something means.
        let centre = host.transform.center
        let spanX = max(host.transform.width, 1e-6)
        let spanZ = max(host.transform.height, 1e-6)
        func across(_ value: Double, _ origin: Double, _ span: Double) -> Double {
            min(1, max(0, (value - origin) / span + 0.5))
        }
        let seat = mesh.top(
            from: across(object.transform.x - object.transform.width / 2, centre.x, spanX),
            across(object.transform.y - object.transform.height / 2, centre.y, spanZ),
            to: across(object.transform.x + object.transform.width / 2, centre.x, spanX),
            across(object.transform.y + object.transform.height / 2, centre.y, spanZ)
        ) ?? 0.6
        return height * seat + roofLift
    }

    /// The mesh a building is actually drawn from, for anything that needs to
    /// know its shape rather than just its size.
    static func hostMesh(of object: PlanObject, metrics: [String: ModelBounds]) -> ModelBounds? {
        guard case let .building(meshes, _) = SceneCatalog.look(for: object).massing,
              let choice = chooseBuilding(
                  meshes: meshes,
                  width: object.transform.width,
                  depth: object.transform.height,
                  seed: object.id,
                  metrics: metrics
              ) else { return nil }
        return metrics[choice.model]
    }

    /// What a building will actually stand at, for anything that has to go on
    /// top of it. Recomputed rather than remembered — the alternative is a
    /// cache that goes stale the first time the catalog changes.
    static func buildingHeight(of object: PlanObject, metrics: [String: ModelBounds]) -> Double? {
        guard case let .building(meshes, height) = SceneCatalog.look(for: object).massing else {
            return nil
        }
        let width = object.transform.width
        let depth = object.transform.height
        guard let choice = chooseBuilding(
            meshes: meshes, width: width, depth: depth, seed: object.id, metrics: metrics
        ), let bounds = metrics[choice.model] else { return nil }
        let proportional = proportionalHeight(bounds: bounds, choice: choice, width: width, depth: depth)
        return min(max(proportional, height * 0.7), height * 1.45)
    }

    /// Where the way in is, if there is a house to measure it from.
    static func gatePoint(of plot: Plot, variant: Variant) -> Point? {
        guard let house = variant.objects.first(where: {
            ObjectLibrary.houseTypeIDs.contains($0.typeId)
        }) else { return nil }
        return PathsAndFences.findGatePoint(
            boundary: plot.boundary,
            houseCenter: house.transform.center,
            waterfrontBounds: WaterfrontModel.bounds(of: plot)
        )
    }

    /// How far the hardstanding reaches out from the garage door.
    public static let drivewayReach = 5.0

    /// A slab of hardstanding from the garage out towards the gate.
    ///
    /// The garage door already faces the gate — the placer turns it that way
    /// and the door is drawn on the wall that looks at it — but there was
    /// nothing to drive on, so the car stood on grass in front of a door with
    /// no approach.
    static func driveway(for object: PlanObject, towards gate: Point) -> SceneSlab {
        let transform = object.transform
        let centre = transform.center
        let dx = gate.x - centre.x
        let dy = gate.y - centre.y
        let length = (dx * dx + dy * dy).squareRoot()
        let unit = length > 1e-6 ? (x: dx / length, y: dy / length) : (x: 0.0, y: 1.0)
        // Out of the door, and wide enough to open a car door beside it.
        let half = max(1.7, min(transform.width, transform.height) / 2)
        let across = (x: -unit.y * half, y: unit.x * half)
        let start = Point(
            x: centre.x + unit.x * min(transform.width, transform.height) * 0.2,
            y: centre.y + unit.y * min(transform.width, transform.height) * 0.2
        )
        let end = Point(x: centre.x + unit.x * drivewayReach, y: centre.y + unit.y * drivewayReach)
        return SceneSlab(
            id: object.id + "-driveway",
            polygon: [
                Point(x: start.x + across.x, y: start.y + across.y),
                Point(x: end.x + across.x, y: end.y + across.y),
                Point(x: end.x - across.x, y: end.y - across.y),
                Point(x: start.x - across.x, y: start.y - across.y),
            ],
            top: Ground.hardstanding,
            thickness: 0,
            colour: drivewayColour,
            objectId: object.id
        )
    }

    // MARK: - Boundary

    static let fenceMesh = "town/fence"
    static let gateMesh = "town/fence-gate"
    public static let fenceHeight = 1.5

    /// How wide a hole to leave in a fence for its gate.
    public static let gateWidth = 3.4

    static func fences(
        _ variant: Variant,
        _ plot: Plot,
        into scene: inout Scene3D,
        metrics: [String: ModelBounds]
    ) {
        guard let bounds = metrics[fenceMesh], bounds.depth > 0 else { return }
        // Where the way in is. The perimeter fence was drawn as an unbroken
        // run right across it, so the plan had a path that walked up to a
        // fence and stopped — "нормальных ворот с заездом так и не появилось".
        let houseCentre = variant.objects
            .first { ObjectLibrary.houseTypeIDs.contains($0.typeId) }?
            .transform.center
        let gate: Point? = houseCentre.map {
            PathsAndFences.findGatePoint(
                boundary: plot.boundary,
                houseCenter: $0,
                waterfrontBounds: WaterfrontModel.bounds(of: plot)
            )
        }
        // Panels are placed end to end at close to their natural length, so
        // the pickets keep their proportions however long the run is.
        let naturalPanel = 2.4

        for (line, fence) in variant.fences.enumerated() {
            for step in 0..<max(0, fence.points.count - 1) {
                let a = fence.points[step]
                let b = fence.points[step + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let run = (dx * dx + dy * dy).squareRoot()
                guard run > 0.2 else { continue }
                let panels = max(1, Int((run / naturalPanel).rounded()))
                let panelLength = run / Double(panels)
                // The mesh runs along its own Z, so the yaw that points it
                // down the fence is measured from +Y in the plan.
                let yaw = -atan2(dx, dy)
                for panel in 0..<panels {
                    let t = (Double(panel) + 0.5) / Double(panels)
                    let centre = Point(x: a.x + dx * t, y: a.y + dy * t)
                    // Leave the gateway open, and stand a gate in it.
                    if fence.gated, let gate, distance(centre, gate) < gateWidth / 2 {
                        continue
                    }
                    if let node = ModelPlacement.node(
                        id: "fence-\(line)-\(step)-\(panel)",
                        model: fenceMesh,
                        centre: centre,
                        yaw: yaw,
                        fit: .footprint(height: fenceHeight),
                        footprint: Size(width: bounds.width, height: panelLength),
                        metrics: metrics
                    ) {
                        scene.meshes.append(node)
                    }
                }

                // The gate itself, square in the gap and facing down the run.
                if fence.gated, let gate,
                   let onSegment = nearestPoint(to: gate, from: a, to: b),
                   distance(onSegment, gate) < 0.5,
                   let gateBounds = metrics[gateMesh],
                   let node = ModelPlacement.node(
                       id: "gate-\(line)-\(step)",
                       model: gateMesh,
                       centre: onSegment,
                       yaw: yaw,
                       fit: .footprint(height: fenceHeight * 1.15),
                       footprint: Size(width: gateBounds.width, height: gateWidth),
                       metrics: metrics
                   ) {
                    scene.meshes.append(node)
                }
            }
        }
    }

    /// The closest point of a segment to `target`, or nil if the segment is a
    /// point.
    static func nearestPoint(to target: Point, from a: Point, to b: Point) -> Point? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-9 else { return nil }
        let t = min(max(((target.x - a.x) * dx + (target.y - a.y) * dy) / lengthSquared, 0), 1)
        return Point(x: a.x + dx * t, y: a.y + dy * t)
    }

    // MARK: -

    /// A point given relative to a centre, turned with it.
    static func rotate(_ local: Point, by radians: Double, around centre: Point) -> Point {
        let cosine = cos(radians)
        let sine = sin(radians)
        return Point(
            x: centre.x + local.x * cosine - local.y * sine,
            y: centre.y + local.x * sine + local.y * cosine
        )
    }

    static func inset(_ polygon: [Point], by amount: Double) -> [Point] {
        guard polygon.count > 2 else { return polygon }
        let centre = Point(
            x: polygon.reduce(0) { $0 + $1.x } / Double(polygon.count),
            y: polygon.reduce(0) { $0 + $1.y } / Double(polygon.count)
        )
        return polygon.map { point in
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance > amount else { return point }
            let factor = (distance - amount) / distance
            return Point(x: centre.x + dx * factor, y: centre.y + dy * factor)
        }
    }
}

/// The footprint an object occupies, honouring the L-shaped house.
enum Massing3D {
    static func footprint(of object: PlanObject) -> [Point] {
        if object.typeId == "house-l" { return LShape.footprint(of: object.transform) }
        return object.transform.corners
    }
}

/// Water colours, shared with the flat plan so the two views agree.
public struct WaterPalette: Equatable, Sendable {
    public let deep: Int
    public let shallow: Int
    public let bank: Int
    public let weed: Int
    public let depth: Double

    /// How far the surface sits below grade.
    ///
    /// A lip rather than a basin, and that is a limitation admitted rather
    /// than a choice. Water is drawn as an extruded polygon, and an extruded
    /// polygon cannot express a hole in the ground: sink it half a metre and
    /// the plot's own edge has half a metre of nothing above the water where
    /// the river meets the boundary, which from the far side of an orbit is a
    /// bright gap along the whole bank. At a few centimetres the gap is
    /// narrower than the line weight and the shading carries the depth
    /// instead.
    public static func of(_ type: WaterfrontType) -> WaterPalette {
        switch type {
        case .river: return WaterPalette(deep: 0x24617f, shallow: 0x6fa8bd, bank: 0xc6bda4, weed: 0x6f8f4a, depth: 0.10)
        case .lake: return WaterPalette(deep: 0x175371, shallow: 0x7cb8d1, bank: 0xd8cfb2, weed: 0x5f8a44, depth: 0.12)
        case .pond: return WaterPalette(deep: 0x335e4c, shallow: 0x76a071, bank: 0x9c8f6a, weed: 0x4e7a33, depth: 0.08)
        }
    }
}
