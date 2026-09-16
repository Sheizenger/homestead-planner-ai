import Foundation
import HomesteadEngine

/// One light for the whole scene.
///
/// It follows the camera's bearing rather than sitting at a fixed compass
/// point, and that is not a stylistic choice — it is what the measurement
/// said. With the sun nailed to the north-east, orbiting the plot walks the
/// scene straight back into the cardboard problem this type was written to
/// fix: over a full turn, a quarter of it (yaw 15°–90°) leaves *both* visible
/// walls of an axis-aligned building at exactly ambient — zero contrast, a
/// flat cut-out — and another quarter leaves them 0.04 apart, which is not
/// visible. Half the orbit, unlit.
///
/// A light carried with the camera keeps the same wall-to-wall contrast at
/// every angle, and keeps the shading and the cast shadows agreeing with each
/// other, which is what actually reads. The bearing is the one the fixed sun
/// had at the isometric default — over the viewer's right shoulder and a
/// little beyond the scene — so the view the plan opens at is unchanged to
/// the last bit: `SceneLight.following(Camera3D())` *is* the old constant.
///
/// The price is that the sun is no longer at a compass point, so shadows
/// swing as you orbit. In a plan drawn at 1:200 nobody traces a shadow back
/// to a bearing, and nothing here claims to be a solar study; a building with
/// two identical grey walls is noticed immediately.
public struct SceneLight: Sendable {
    /// Direction *to* the sun. Unit length is not required — `brightness`
    /// normalises — but this is kept unit-ish so the numbers read as angles.
    public let toSun: (x: Double, y: Double, z: Double)

    public init(toSun: (x: Double, y: Double, z: Double)) {
        self.toSun = toSun
    }

    /// How the light sits relative to the camera, in the camera's own
    /// horizontal frame: `across` is the viewer's right, `into` is away from
    /// the viewer. Both are the components the old fixed `(0.45, -0.55, 0.70)`
    /// had at yaw −45°, which is why the default view does not move.
    private static let across = 2.0.squareRoot() / 2
    private static let into = -0.05 * 2.0.squareRoot()
    private static let elevation = 0.70

    public static func following(_ camera: Camera3D) -> SceneLight {
        // The camera's horizontal basis: `right` is the screen's x axis on
        // the ground, `away` points from the viewer into the scene.
        let right = (x: cos(camera.yaw), y: sin(camera.yaw))
        let away = (x: -sin(camera.yaw), y: cos(camera.yaw))
        return SceneLight(toSun: (
            x: right.x * across + away.x * into,
            y: right.y * across + away.y * into,
            z: elevation
        ))
    }

    /// The light at the view the plan opens at, for anything drawn outside a
    /// camera's context.
    static let isometric = SceneLight.following(Camera3D())

    /// How much of a face's colour survives with no direct light on it.
    /// High, because this is outdoor daylight with sky fill, not a spotlight.
    private static let ambient = 0.58

    /// The brightness a face is painted at when it gets its base colour
    /// untouched. Faces above it are washed toward white, below toward black,
    /// so the palette stays the one the type chose.
    private static let neutral = 0.80

    /// Lambert term for a face with this outward normal, in [0, 1].
    public func brightness(normal: (x: Double, y: Double, z: Double)) -> Double {
        let length = (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot()
        guard length > 0 else { return Self.ambient }
        let dot = (normal.x * toSun.x + normal.y * toSun.y + normal.z * toSun.z) / length
        return Self.ambient + (1 - Self.ambient) * max(0, dot)
    }

    /// The `shade` value `AxoPainter.face` wants: positive darkens, negative
    /// lightens. Derived from the light rather than chosen by eye, so every
    /// object in the scene agrees about where the sun is.
    public func shade(normal: (x: Double, y: Double, z: Double)) -> Double {
        (Self.neutral - brightness(normal: normal)) * 1.2
    }

    /// Where a point `height` metres up lands on the ground, along the light.
    public func shadowOffset(height: Double) -> Point {
        Point(x: -toSun.x / toSun.z * height, y: -toSun.y / toSun.z * height)
    }

    // MARK: - Geometry, which the light has no part in

    /// Outward normal of a vertical wall whose base runs from `a` to `b`,
    /// resolved against the footprint's own centre so it does not depend on
    /// which way round the caller happened to list the edge.
    ///
    /// The perpendicular alone is only outward for one winding, and half the
    /// edges a roof is built from are listed the other way: `longEdges` and
    /// `gableEnds` are ordered so each runs from the ridge's `A` end to its
    /// `B` end, which reverses two of the four. That gave the second slope of
    /// every roof an inward normal, so its overhang was pushed 0.45 m *inside*
    /// the wall — the gap between roof and wall at the gable — and it was
    /// shaded as if facing the sun, which is the pale wedge that came with it.
    public static func wallNormal(from a: Point, to b: Point, about centre: Point? = nil) -> (x: Double, y: Double, z: Double) {
        let perpendicular = (x: b.y - a.y, y: -(b.x - a.x), z: 0.0)
        guard let centre else { return perpendicular }
        let outwardX = (a.x + b.x) / 2 - centre.x
        let outwardY = (a.y + b.y) / 2 - centre.y
        let agrees = perpendicular.x * outwardX + perpendicular.y * outwardY >= 0
        return agrees ? perpendicular : (x: -perpendicular.x, y: -perpendicular.y, z: 0)
    }

    /// Outward normal of a roof plane that rises from eaves edge `a`–`b` to a
    /// ridge `rise` metres above, `run` metres horizontally inward.
    public static func roofNormal(from a: Point, to b: Point, run: Double, rise: Double, about centre: Point? = nil) -> (x: Double, y: Double, z: Double) {
        let wall = wallNormal(from: a, to: b, about: centre)
        let length = (wall.x * wall.x + wall.y * wall.y).squareRoot()
        guard length > 0, run > 0 else { return (0, 0, 1) }
        // Tilt the wall normal up by the pitch: horizontal component scales
        // with the run, vertical with the rise.
        return (x: wall.x / length * rise, y: wall.y / length * rise, z: run)
    }

    public static let up = (x: 0.0, y: 0.0, z: 1.0)
}
