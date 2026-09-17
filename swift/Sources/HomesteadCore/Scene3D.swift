import Foundation
import HomesteadEngine

/// A point in the scene's own space: metres, **Y up**, which is what SceneKit
/// wants.
///
/// The engine works in X-east, Y-south, Z-up — a plan view, where Y going down
/// the page is south. The scene works in X-east, Y-up, Z-south. Swapping the
/// last two axes is the whole conversion, and it happens here and nowhere
/// else: every previous attempt at 3D in this project spread its coordinate
/// conventions across eighteen call sites, and that is exactly why none of
/// them could be changed afterwards.
public struct Vector3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)
    public static let one = Vector3(x: 1, y: 1, z: 1)

    /// A ground point from the engine, lifted to `height` metres.
    public static func ground(_ point: Point, height: Double = 0) -> Vector3 {
        Vector3(x: point.x, y: height, z: point.y)
    }

    /// Back to the engine's plan coordinates, dropping the height.
    public var plan: Point { Point(x: x, y: z) }
}

/// Which way an object faces, in the scene's frame.
///
/// The engine turns objects anticlockwise in its plan view; swapping two axes
/// to get to the scene reverses the handedness, so the same turn is clockwise
/// here. One negation, in one place, pinned by a test — rather than a sign
/// that everybody has to remember.
public func sceneYaw(fromEngineDegrees degrees: Double) -> Double {
    -degrees * .pi / 180
}

/// How a mesh is sized onto the space the plan gives it.
///
/// The distinction matters more than it looks. A plan says "shed, 4 by 3
/// metres", and there is no mesh in any kit that is 4 by 3 metres. Stretching
/// one to fit is right for a modular wall panel — that is what the panel is
/// for — and badly wrong for a tree or a car, which come out as a squashed
/// tree and a squashed car. The first pass at this stretched everything and
/// looked exactly like that.
public enum ModelFit: Equatable, Sendable {
    /// Stretch the mesh's horizontal box to exactly the footprint, and its
    /// height to `height` metres. For the modular pieces a building is
    /// assembled from, where stretching along the panel is the point.
    case footprint(height: Double)
    /// Uniform scale to `height` metres tall, centred on the footprint. For
    /// anything with a shape of its own — a tree, a car, a silo, a boat.
    /// Never distorts.
    case standing(height: Double)
    /// Uniform scale so the mesh's widest horizontal extent is this many
    /// metres. For things sized by how much ground they cover rather than by
    /// how tall they are: a rock, a hay bale, a patch of grass.
    case spanning(Double)
    /// Uniform scale so the mesh fits inside the footprint without exceeding
    /// it in either direction. For a mesh dropped into a space whose
    /// proportions it does not share.
    case inscribed
}

/// One mesh, placed. The whole scene is a list of these, and the renderer's
/// only job is to walk it — which is what keeps the renderer, the one part
/// that cannot be compiled or tested on Linux, small enough to trust.
public struct SceneNode: Identifiable, Equatable, Sendable {
    /// Unique within a scene; the renderer keys its node cache on it.
    public var id: String
    /// `kit/name`, matching `ModelMetrics`.
    public var model: String
    /// Where the mesh's own origin goes, in scene space.
    public var position: Vector3
    public var scale: Vector3
    /// Rotation about the vertical axis, radians.
    public var yaw: Double
    /// Tilt about the node's own horizontal axis, radians, applied after the
    /// yaw. Only one thing in the catalog is not upright — a solar panel —
    /// but a panel lying flat on the grass is unmistakably wrong, and there
    /// is no way to express the tilt in a scale.
    public var pitch: Double
    /// The plan object a click on this node selects. Several nodes share one:
    /// a building is a dozen meshes and all of them are the same building.
    public var objectId: String?
    /// A recolour applied over the kit's atlas, as 0xRRGGBB. The kits are one
    /// texture per kit, so tinting is how two sheds become two *different*
    /// sheds without a second texture.
    public var tint: Int?

    public init(
        id: String,
        model: String,
        position: Vector3,
        scale: Vector3 = .one,
        yaw: Double = 0,
        pitch: Double = 0,
        objectId: String? = nil,
        tint: Int? = nil
    ) {
        self.id = id
        self.model = model
        self.position = position
        self.scale = scale
        self.yaw = yaw
        self.pitch = pitch
        self.objectId = objectId
        self.tint = tint
    }

    /// The footprint the mesh occupies once scaled, for tests and for laying
    /// things out against each other.
    public func size(from bounds: ModelBounds) -> (width: Double, height: Double, depth: Double) {
        (
            width: bounds.width * scale.x,
            height: bounds.height * scale.y,
            depth: bounds.depth * scale.z
        )
    }
}

/// Turning "this mesh, this big, here" into a `SceneNode`.
///
/// Three things go wrong without this and went wrong with it missing: a mesh
/// whose origin is not at its own centre swings out of place when it is
/// turned; a mesh whose origin is not at its own base floats or sinks; and a
/// mesh scaled about its origin moves as well as growing. All three are the
/// same fact — the origin is wherever the modeller left it — and
/// `ModelMetrics` is what makes it answerable.
public enum ModelPlacement {
    public static func scale(for fit: ModelFit, bounds: ModelBounds, footprint: Size) -> Vector3 {
        switch fit {
        case let .footprint(height):
            return Vector3(
                x: safeRatio(footprint.width, bounds.width),
                y: safeRatio(height, bounds.height),
                z: safeRatio(footprint.height, bounds.depth)
            )
        case let .standing(height):
            let uniform = safeRatio(height, bounds.height)
            return Vector3(x: uniform, y: uniform, z: uniform)
        case let .spanning(span):
            let uniform = safeRatio(span, bounds.span)
            return Vector3(x: uniform, y: uniform, z: uniform)
        case .inscribed:
            let uniform = min(
                safeRatio(footprint.width, bounds.width),
                safeRatio(footprint.height, bounds.depth)
            )
            return Vector3(x: uniform, y: uniform, z: uniform)
        }
    }

    /// A mesh standing on the ground at `centre`, facing `yaw`.
    ///
    /// `base` is the ground height under it — non-zero for anything on a deck,
    /// in a basin, or on a slab.
    public static func node(
        id: String,
        model: String,
        centre: Point,
        base: Double = 0,
        yaw: Double = 0,
        pitch: Double = 0,
        fit: ModelFit,
        footprint: Size = Size(width: 1, height: 1),
        objectId: String? = nil,
        tint: Int? = nil,
        metrics: [String: ModelBounds] = ModelMetrics.all
    ) -> SceneNode? {
        guard let bounds = metrics[model] else { return nil }
        let scale = self.scale(for: fit, bounds: bounds, footprint: footprint)

        // The mesh's own centre, in scene units, relative to its origin —
        // then turned, because the node is rotated about its origin and not
        // about the middle of the mesh.
        let offsetX = -bounds.centreX * scale.x
        let offsetZ = -bounds.centreZ * scale.z
        let cosine = cos(yaw)
        let sine = sin(yaw)

        return SceneNode(
            id: id,
            model: model,
            position: Vector3(
                x: centre.x + offsetX * cosine + offsetZ * sine,
                y: base + bounds.baseOffset * scale.y,
                z: centre.y - offsetX * sine + offsetZ * cosine
            ),
            scale: scale,
            yaw: yaw,
            pitch: pitch,
            objectId: objectId,
            tint: tint
        )
    }

    /// Where the middle of a placed mesh's footprint actually ended up — the
    /// inverse of the offset above, and the thing a test should assert on.
    public static func footprintCentre(of node: SceneNode, metrics: [String: ModelBounds] = ModelMetrics.all) -> Point? {
        guard let bounds = metrics[node.model] else { return nil }
        let offsetX = bounds.centreX * node.scale.x
        let offsetZ = bounds.centreZ * node.scale.z
        let cosine = cos(node.yaw)
        let sine = sin(node.yaw)
        return Point(
            x: node.position.x + offsetX * cosine + offsetZ * sine,
            y: node.position.z - offsetX * sine + offsetZ * cosine
        )
    }

    private static func safeRatio(_ wanted: Double, _ available: Double) -> Double {
        guard available > 1e-9, wanted.isFinite else { return 1 }
        return wanted / available
    }
}
