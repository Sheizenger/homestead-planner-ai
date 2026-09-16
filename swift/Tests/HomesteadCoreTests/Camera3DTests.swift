import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

/// The whole point of the camera is that it changes nothing until it moves.
///
/// The axonometric view hardcoded one projection, one depth order and one
/// visibility test, in eighteen places between them. They are the same camera
/// written down three times; these tests are the proof, so the generalisation
/// can be trusted not to have moved the picture.
struct Camera3DTests {
    private let camera = Camera3D()

    /// The old projection, with its rounded constants restored to exact
    /// cos30/sin30. `Axonometry` carried `0.866` and `0.5`, a 3e-5 relative
    /// error worth a couple of millimetres on screen; comparing against the
    /// rounded value would pin the error rather than the projection.
    private func legacyProject(_ x: Double, _ y: Double, _ z: Double) -> Point {
        Point(x: (x - y) * cos(Double.pi / 6), y: (x + y) * sin(Double.pi / 6) - z)
    }

    @Test func defaultsReproduceTheOldProjection() {
        for (x, y, z) in [(0.0, 0.0, 0.0), (12.0, 7.0, 3.8), (-40.0, 55.0, 0.0), (3.0, -9.0, 12.0)] {
            let now = camera.project(x: x, y: y, z: z)
            let before = legacyProject(x, y, z)
            #expect(abs(now.x - before.x) < 1e-12, Comment(rawValue: "x at \(x),\(y),\(z)"))
            #expect(abs(now.y - before.y) < 1e-12, Comment(rawValue: "y at \(x),\(y),\(z)"))
        }
    }

    /// `x + y`, which is what every depth sort in the view used, ordered the
    /// same way — the camera adds the height term it was missing.
    @Test func theDepthOrderMatchesTheOldSortAtTheDefaultCamera() {
        // Distinct sums: `x + y` ties at 10 for both (10,0) and (0,10), and a
        // tie is broken by whatever the sort does, not by either rule.
        let points = [(0.0, 0.0), (10.0, 0.0), (0.0, 13.0), (7.0, 3.0), (-5.0, 20.0)]
        let byCamera = points.sorted { camera.depthKey(x: $0.0, y: $0.1, z: 0) < camera.depthKey(x: $1.0, y: $1.1, z: 0) }
        let byLegacy = points.sorted { $0.0 + $0.1 < $1.0 + $1.1 }
        #expect(byCamera.map(\.0) == byLegacy.map(\.0))
        #expect(byCamera.map(\.1) == byLegacy.map(\.1))
    }

    /// And `normal.x + normal.y > 0` is this test for one camera. Vertical
    /// walls only, which is all that test was ever applied to.
    @Test func visibilityMatchesTheOldTestForVerticalWalls() {
        for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 12) {
            let normal = (x: cos(angle), y: sin(angle), z: 0.0)
            #expect(camera.faces(normal) == (normal.x + normal.y > 0), Comment(rawValue: "\(angle)"))
        }
    }

    /// The thing none of it could do. A quarter turn has to show the other
    /// two walls of a box and hide the two that were showing.
    @Test func turningAQuarterShowsTheOtherTwoWalls() {
        let east = (x: 1.0, y: 0.0, z: 0.0)
        let west = (x: -1.0, y: 0.0, z: 0.0)
        #expect(camera.faces(east))
        #expect(!camera.faces(west))

        let turned = Camera3D(yaw: Camera3D.isometricYaw + .pi / 2)
        #expect(!turned.faces(east))
        #expect(turned.faces(west))
    }

    /// The ground stays the ground however far it turns: the top of a box is
    /// always toward the camera, its underside never.
    @Test func theSkyFacingSideIsAlwaysVisible() {
        for turn in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
            let camera = Camera3D(yaw: turn)
            #expect(camera.faces(AxoUp), Comment(rawValue: "\(turn)"))
            #expect(!camera.faces((x: 0, y: 0, z: -1)), Comment(rawValue: "\(turn)"))
        }
    }

    /// Hit testing inverts the projection at ground level; it has to survive
    /// the camera moving.
    @Test func theGroundInverseRoundTripsAtAnyYaw() {
        for turn in stride(from: -Double.pi, through: .pi, by: .pi / 5) {
            let camera = Camera3D(yaw: turn)
            for point in [Point(x: 0, y: 0), Point(x: 17, y: -4), Point(x: -23, y: 31)] {
                let back = camera.groundPoint(camera.project(point, z: 0))
                #expect(abs(back.x - point.x) < 1e-9, Comment(rawValue: "\(turn) \(point)"))
                #expect(abs(back.y - point.y) < 1e-9, Comment(rawValue: "\(turn) \(point)"))
            }
        }
    }

    /// A horizontal circle is full width across and foreshortened vertically,
    /// whatever the yaw — which is why a tank's lid can be an axis-aligned
    /// ellipse at every camera angle instead of a real projected conic.
    @Test func aHorizontalCircleForeshortensOnlyVertically() {
        let base = camera.horizontalEllipse(radius: 2)
        for turn in stride(from: 0.0, to: 2 * .pi, by: .pi / 7) {
            let turned = Camera3D(yaw: turn).horizontalEllipse(radius: 2)
            #expect(abs(turned.rx - base.rx) < 1e-12, Comment(rawValue: "\(turn)"))
            #expect(abs(turned.ry - base.ry) < 1e-12, Comment(rawValue: "\(turn)"))
        }
        // And it matches the `r * 1.414 * cos30` / `r * 1.414 * sin30` the
        // view spelled out by hand.
        #expect(abs(base.rx - 2 * 1.41421356 * 0.8660254) < 1e-6)
        #expect(abs(base.ry - 2 * 1.41421356 * 0.5) < 1e-6)
    }
}

private let AxoUp = (x: 0.0, y: 0.0, z: 1.0)

// MARK: - Orbiting

extension Camera3DTests {
    /// Dragging right has to turn the scene the way a turntable would: the
    /// part of the plot nearest the camera follows the finger. Get the sign
    /// wrong and the view rotates away from the drag, which reads as broken
    /// rather than as a different convention.
    @Test func increasingYawSwingsTheNearestCornerToTheRight() {
        let camera = Camera3D()
        let toCamera = camera.toCamera
        // A point on the ground on the camera's side of the plot.
        let near = Point(x: toCamera.x * 10, y: toCamera.y * 10)
        let before = camera.project(near).x
        let after = camera.turned(byYaw: 0.05).project(near).x
        #expect(after > before)
    }

    /// And dragging down tips the plot's top toward you, so the near edge
    /// travels down the screen as the pitch rises.
    @Test func increasingPitchSwingsTheNearestCornerDown() {
        let camera = Camera3D()
        let toCamera = camera.toCamera
        let near = Point(x: toCamera.x * 10, y: toCamera.y * 10)
        let before = camera.project(near).y
        let after = camera.turned(byYaw: 0, pitch: 0.05).project(near).y
        #expect(after > before)
    }

    @Test func pitchStopsShortOfBothDegenerateEnds() {
        #expect(Camera3D().turned(byYaw: 0, pitch: -10).pitch == Camera3D.minPitch)
        #expect(Camera3D().turned(byYaw: 0, pitch: 10).pitch == Camera3D.maxPitch)
        // Neither end collapses the ground plane, which is the reason the
        // clamp exists: `groundPoint` divides by sin(pitch).
        for pitch in [Camera3D.minPitch, Camera3D.maxPitch] {
            let camera = Camera3D(yaw: 0.3, pitch: pitch)
            let round = camera.groundPoint(camera.project(Point(x: 7, y: -3)))
            #expect(abs(round.x - 7) < 1e-9)
            #expect(abs(round.y + 3) < 1e-9)
        }
    }

    @Test func yawWrapsInsteadOfAccumulating() {
        let spun = (0..<40).reduce(Camera3D()) { camera, _ in camera.turned(byYaw: 0.5) }
        #expect(abs(spun.yaw) <= Double.pi)
        // Twenty radians of dragging still leaves the camera pointing
        // somewhere real: wrapping is congruent, not a reset.
        let unwrapped = Camera3D.isometricYaw + 20
        #expect(abs(cos(spun.yaw) - cos(unwrapped)) < 1e-9)
        #expect(abs(sin(spun.yaw) - sin(unwrapped)) < 1e-9)
    }

    @Test func defaultCameraKnowsItIsTheOneThePlanOpensAt() {
        #expect(Camera3D().isIsometric)
        #expect(!Camera3D().turned(byYaw: 0.01).isIsometric)
        // A full turn round is the same camera, however it was reached.
        #expect(Camera3D().turned(byYaw: 2 * .pi).isIsometric)
    }

    /// The pivot is what makes an orbit feel like a turntable rather than a
    /// chase: the point being held stays exactly where it was on screen.
    @Test func turningHoldsThePivotStillOnScreen() {
        let pivot = Point(x: 18, y: -7)
        let old = Camera3D()
        for (yawStep, pitchStep) in [(0.4, 0.0), (0.0, 0.2), (-1.3, -0.25), (3.0, 0.3)] {
            let new = old.turned(byYaw: yawStep, pitch: pitchStep)
            var viewport = Viewport(offset: Point(x: -4, y: 2), scale: 9)
            let before = viewport.toScreen(old.project(pivot))
            viewport.turn(from: old, to: new, holding: pivot)
            let after = viewport.toScreen(new.project(pivot))
            #expect(abs(after.x - before.x) < 1e-9)
            #expect(abs(after.y - before.y) < 1e-9)
        }
    }

    /// Turning moves the camera, not the zoom. A re-fit would have been the
    /// easy way to keep the plot in frame and it would have changed the scale
    /// under the user's hand mid-drag.
    @Test func turningLeavesTheScaleAlone() {
        var viewport = Viewport(offset: Point(x: 0, y: 0), scale: 11)
        let old = Camera3D()
        viewport.turn(from: old, to: old.turned(byYaw: 1.1, pitch: 0.2), holding: Point(x: 3, y: 3))
        #expect(viewport.scale == 11)
    }
}
