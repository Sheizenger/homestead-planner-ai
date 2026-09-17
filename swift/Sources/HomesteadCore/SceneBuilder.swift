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

        for object in variant.objects {
            place(object, into: &scene, metrics: metrics)
        }
        fences(variant, into: &scene, metrics: metrics)
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
                    top: 0.04,
                    thickness: 0,
                    colour: pathColour
                ))
            }
        }
    }

    // MARK: - Objects

    static func place(_ object: PlanObject, into scene: inout Scene3D, metrics: [String: ModelBounds]) {
        let look = SceneCatalog.look(for: object)
        let transform = object.transform
        let footprint = Size(width: transform.width, height: transform.height)
        let yaw = sceneYaw(fromEngineDegrees: transform.rotationDeg)

        switch look.massing {
        case let .building(meshes, height):
            scene.meshes += building(
                object, meshes: meshes, height: height, tint: look.tint, metrics: metrics
            )

        case let .single(model, fit):
            if let node = ModelPlacement.node(
                id: object.id, model: model, centre: transform.center, yaw: yaw,
                fit: fit, footprint: footprint, objectId: object.id, tint: look.tint, metrics: metrics
            ) {
                scene.meshes.append(node)
            }

        case let .scatter(models, density, height):
            scene.meshes += scatter(
                object, models: models, density: density, height: height,
                tint: look.tint, metrics: metrics
            )

        case let .rows(model, spacing, height, alongLongAxis, tilt):
            scene.meshes += rows(
                object, model: model, spacing: spacing, height: height,
                alongLongAxis: alongLongAxis, tilt: tilt, tint: look.tint, metrics: metrics
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
            scene.slabs.append(SceneSlab(
                id: object.id + "-coping", polygon: Massing3D.footprint(of: object),
                top: 0.16, thickness: 0.16, colour: 0xD8D2C4, objectId: object.id
            ))
            scene.slabs.append(SceneSlab(
                id: object.id, polygon: inset(Massing3D.footprint(of: object), by: 0.5),
                top: -depth * 0.25, thickness: depth, colour: colour, objectId: object.id
            ))
        }

        scene.meshes += props(object, look: look, metrics: metrics)
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
        let area = transform.width * transform.height
        let wanted = max(1, min(90, Int((area * density).rounded())))
        let radians = transform.rotationDeg * .pi / 180

        var nodes: [SceneNode] = []
        for index in 0..<wanted {
            let model = models[index % models.count]
            let local = Point(
                x: SceneNoise.jitter(object.id, index, 1, transform.width / 2 - 1),
                y: SceneNoise.jitter(object.id, index, 2, transform.height / 2 - 1)
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

    /// Crops, vines, beds, panels: one stretched mesh per row.
    ///
    /// One mesh per *plant* would be tens of thousands of nodes on a grain
    /// field and would read as noise anyway; a row of planting seen from
    /// across a plot is a strip, and a strip is what this draws.
    static func rows(
        _ object: PlanObject,
        model: String,
        spacing: Double,
        height: Double,
        alongLongAxis: Bool,
        tilt: Double,
        tint: Int?,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let longIsX = (transform.width >= transform.height) == alongLongAxis
        let rowLength = longIsX ? transform.width : transform.height
        let across = longIsX ? transform.height : transform.width
        guard rowLength > 0.5, across > 0.5, spacing > 0.1 else { return [] }

        let count = max(1, min(40, Int((across / spacing).rounded(.down))))
        let step = across / Double(count)
        let radians = transform.rotationDeg * .pi / 180
        let bedWidth = min(step * 0.62, spacing * 0.62)

        var nodes: [SceneNode] = []
        for row in 0..<count {
            let offset = (Double(row) + 0.5) * step - across / 2
            let local = longIsX ? Point(x: 0, y: offset) : Point(x: offset, y: 0)
            let footprint = longIsX
                ? Size(width: rowLength * 0.94, height: bedWidth)
                : Size(width: bedWidth, height: rowLength * 0.94)
            if var node = ModelPlacement.node(
                id: "\(object.id)-row\(row)",
                model: model,
                centre: rotate(local, by: radians, around: transform.center),
                yaw: sceneYaw(fromEngineDegrees: transform.rotationDeg),
                pitch: tilt,
                fit: .footprint(height: height),
                footprint: footprint,
                objectId: object.id,
                tint: tint,
                metrics: metrics
            ) {
                // Tilting about the node's own origin would swing half the
                // panel underground; a leaning array stands on legs.
                if tilt != 0 {
                    node.position.y += abs(sin(tilt)) * footprint.height / 2 + 0.5
                }
                nodes.append(node)
            }
        }
        return nodes
    }

    static func props(
        _ object: PlanObject,
        look: SceneCatalog.Look,
        metrics: [String: ModelBounds]
    ) -> [SceneNode] {
        let transform = object.transform
        let radians = transform.rotationDeg * .pi / 180
        var nodes: [SceneNode] = []
        for (index, prop) in look.props.enumerated() {
            for copy in 0..<prop.count {
                let spread = prop.count > 1 ? Double(copy) - Double(prop.count - 1) / 2 : 0
                let local = Point(
                    x: prop.offset.x * transform.width / 2 + spread * 1.1
                        + SceneNoise.jitter(object.id, index * 10 + copy, 5, 0.3),
                    y: prop.offset.y * transform.height / 2
                        + SceneNoise.jitter(object.id, index * 10 + copy, 6, 0.3)
                )
                if let node = ModelPlacement.node(
                    id: "\(object.id)-prop\(index)-\(copy)",
                    model: prop.model,
                    centre: rotate(local, by: radians, around: transform.center),
                    yaw: sceneYaw(fromEngineDegrees: transform.rotationDeg) + prop.yaw
                        + SceneNoise.jitter(object.id, index * 10 + copy, 7, 0.25),
                    fit: prop.fit,
                    objectId: object.id,
                    metrics: metrics
                ) {
                    nodes.append(node)
                }
            }
        }
        return nodes
    }

    // MARK: - Boundary

    static let fenceMesh = "town/fence"
    static let gateMesh = "town/fence-gate"
    public static let fenceHeight = 1.5

    static func fences(_ variant: Variant, into scene: inout Scene3D, metrics: [String: ModelBounds]) {
        guard let bounds = metrics[fenceMesh], bounds.depth > 0 else { return }
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
            }
        }
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
