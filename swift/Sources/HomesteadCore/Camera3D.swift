import Foundation
import HomesteadEngine

/// An orthographic camera you can turn around the plot.
///
/// The axonometric view was built on three hardcoded assumptions, all of which
/// break the moment the camera moves: the projection was `(x−y)·cos30`,
/// `(x+y)·sin30 − z`; depth order was `x + y`; and a face was visible when
/// `normal.x + normal.y > 0`. Eleven copies of that last test, seven of the
/// sort. Rotation cannot be bolted onto any of them, which is why every fix
/// was another special case.
///
/// They are all the same camera written down three times. That projection *is*
/// an orthographic camera at yaw −45° and pitch 35.264° — the classic
/// isometric pair — so generalising costs nothing and changes nothing at the
/// default: `defaultsReproduceTheOldProjection` pins that to 1e-12.
public struct Camera3D: Equatable, Sendable {
    /// Rotation about the vertical axis, radians. −45° is the isometric view
    /// the plan has always had.
    public var yaw: Double
    /// Elevation above the ground plane, radians. 35.264° = asin(1/√3) is what
    /// makes the three axes foreshorten equally.
    public var pitch: Double

    public static let isometricYaw = -Double.pi / 4
    public static let isometricPitch = asin(1.0 / 3.0.squareRoot())

    /// How far the camera may be lowered and raised.
    ///
    /// Not a matter of taste: at pitch 0 the ground plane is edge-on, so the
    /// whole plot collapses to a line and `groundPoint` divides by zero when
    /// hit-testing a click; at pitch 90° the view is a flat plan and every
    /// wall is edge-on instead. Both ends are degenerate rather than merely
    /// ugly, so the orbit stops short of them.
    public static let minPitch = 12.0 * .pi / 180
    public static let maxPitch = 78.0 * .pi / 180

    public static func clampPitch(_ pitch: Double) -> Double {
        min(max(pitch, minPitch), maxPitch)
    }

    /// Yaw folded into (−π, π]. Unbounded yaw would work — every use of it
    /// goes through `sin`/`cos` — but it would accumulate over a session of
    /// dragging until the double loses resolution, and it would make a saved
    /// camera read as "yaw 37.7 rad".
    public static func wrapYaw(_ yaw: Double) -> Double {
        let turn = 2 * Double.pi
        var wrapped = yaw.truncatingRemainder(dividingBy: turn)
        if wrapped <= -Double.pi { wrapped += turn }
        if wrapped > Double.pi { wrapped -= turn }
        return wrapped
    }

    /// The camera turned by the given deltas, wrapped and clamped. Every
    /// interaction that moves the camera goes through this, so none of them
    /// can produce an angle the rest of the view can't draw.
    public func turned(byYaw yawDelta: Double, pitch pitchDelta: Double = 0) -> Camera3D {
        Camera3D(
            yaw: Self.wrapYaw(yaw + yawDelta),
            pitch: Self.clampPitch(pitch + pitchDelta)
        )
    }

    /// True when this is the view the plan opens at.
    public var isIsometric: Bool {
        abs(Self.wrapYaw(yaw - Self.isometricYaw)) < 1e-9 && abs(pitch - Self.isometricPitch) < 1e-9
    }

    public init(yaw: Double = Camera3D.isometricYaw, pitch: Double = Camera3D.isometricPitch) {
        self.yaw = yaw
        self.pitch = pitch
    }

    /// Scale that keeps a metre the same size on screen as the old fixed
    /// projection drew it, so switching to the camera doesn't resize the plan.
    /// Exact, where the old projection carried `0.866` and `0.5` rounded to
    /// three places — a 3e-5 relative error, which at plot scale is a couple
    /// of millimetres on screen. Strictly better, and the reason the parity
    /// test compares against exact cos30 rather than against the constant.
    public static let unitScale = 2.0.squareRoot() * cos(Double.pi / 6)

    /// World metres to the view's own 2D space, before the `Viewport` pan and
    /// zoom. `y` grows downward on screen, as it does everywhere else here.
    public func project(x: Double, y: Double, z: Double) -> Point {
        let across = x * cos(yaw) + y * sin(yaw)
        let into = -x * sin(yaw) + y * cos(yaw)
        return Point(
            x: across * Self.unitScale,
            y: (into * sin(pitch) - z * cos(pitch)) * Self.unitScale
        )
    }

    public func project(_ point: Point, z: Double = 0) -> Point {
        project(x: point.x, y: point.y, z: z)
    }

    /// Unit vector from the scene toward the camera.
    public var toCamera: (x: Double, y: Double, z: Double) {
        (x: -sin(yaw) * cos(pitch), y: cos(yaw) * cos(pitch), z: sin(pitch))
    }

    /// Painter's-algorithm sort key: ascending is far to near.
    ///
    /// At the default camera this is `(x + y + z) / √3`, which is the old
    /// `x + y` sort with the height term it was missing.
    public func depthKey(x: Double, y: Double, z: Double) -> Double {
        let camera = toCamera
        return x * camera.x + y * camera.y + z * camera.z
    }

    public func depthKey(_ point: Point, z: Double = 0) -> Double {
        depthKey(x: point.x, y: point.y, z: z)
    }

    /// True when a face with this outward normal is turned toward the camera.
    /// Replaces `normal.x + normal.y > 0`, which is this test written out for
    /// one particular camera.
    public func faces(_ normal: (x: Double, y: Double, z: Double)) -> Bool {
        let camera = toCamera
        return normal.x * camera.x + normal.y * camera.y + normal.z * camera.z > 0
    }

    /// A horizontal circle of radius `r` projects to an axis-aligned ellipse:
    /// full width across, foreshortened by `sin(pitch)` vertically, whatever
    /// the yaw. The old code spelled this `r * 1.414 * cos30` and
    /// `r * 1.414 * sin30`, which is the same thing at the default camera.
    public func horizontalEllipse(radius: Double) -> (rx: Double, ry: Double) {
        (rx: radius * Self.unitScale, ry: radius * Self.unitScale * sin(pitch))
    }

    /// Inverse at ground level, for hit-testing a click.
    public func groundPoint(_ projected: Point) -> Point {
        let across = projected.x / Self.unitScale
        let into = projected.y / (Self.unitScale * sin(pitch))
        return Point(
            x: across * cos(yaw) - into * sin(yaw),
            y: across * sin(yaw) + into * cos(yaw)
        )
    }
}
