import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

/// The light is the reason a box reads as a box. These tests exist because
/// making the camera turnable quietly broke it, and nothing in the app layer
/// can be run here to notice.
struct SceneLightTests {
    /// The four walls of an axis-aligned building.
    private let walls: [(x: Double, y: Double, z: Double)] = [
        (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)
    ]

    private func visibleWalls(from camera: Camera3D) -> [(x: Double, y: Double, z: Double)] {
        walls.filter { camera.faces($0) }
    }

    /// How much of its full width the most foreshortened visible wall keeps.
    /// Near a quadrant boundary this goes to zero: the wall is edge-on, and
    /// whatever tone it is painted covers no pixels.
    private func narrowestWall(from camera: Camera3D) -> Double {
        let visible = visibleWalls(from: camera)
        guard visible.count > 1 else { return 0 }
        return visible
            .map { abs($0.x * camera.toCamera.x + $0.y * camera.toCamera.y + $0.z * camera.toCamera.z) }
            .min() ?? 0
    }

    /// Difference in brightness between the lightest and darkest wall a
    /// viewer can see — how much the building reads as having sides.
    private func wallContrast(at camera: Camera3D) -> Double? {
        let visible = visibleWalls(from: camera)
        guard visible.count > 1 else { return nil }
        let light = SceneLight.following(camera)
        let values = visible.map { light.brightness(normal: $0) }
        return values.max()! - values.min()!
    }

    /// The generalisation must not move the picture: at the view the plan
    /// opens at, the light is the exact constant the look was tuned against.
    @Test func theDefaultViewKeepsTheSunItAlwaysHad() {
        let light = SceneLight.following(Camera3D())
        #expect(abs(light.toSun.x - 0.45) < 1e-12)
        #expect(abs(light.toSun.y - (-0.55)) < 1e-12)
        #expect(abs(light.toSun.z - 0.70) < 1e-12)
    }

    /// The measurement that forced the camera-following light. With the sun
    /// nailed to the north-east, a full quadrant of the orbit put *both*
    /// visible walls at exactly ambient: two identical grey rectangles, the
    /// cardboard look the shading exists to avoid.
    @Test func aFixedSunWouldLeaveHalfTheOrbitFlat() {
        let fixed = SceneLight(toSun: (x: 0.45, y: -0.55, z: 0.70))
        var flatAngles = 0
        var total = 0
        for step in 0..<72 {
            let camera = Camera3D(yaw: -.pi + Double(step) / 72 * 2 * .pi)
            let visible = visibleWalls(from: camera)
            guard visible.count > 1 else { continue }
            total += 1
            let values = visible.map { fixed.brightness(normal: $0) }
            if values.max()! - values.min()! < 0.05 { flatAngles += 1 }
        }
        #expect(total > 60)
        // Not a marginal effect: it is half the turn.
        #expect(Double(flatAngles) / Double(total) > 0.45)
    }

    /// And the fix: every angle reads the way the default angle does.
    ///
    /// The bar is set where the measurement put it. Within about 12° of a
    /// quadrant boundary one of the two walls turns edge-on, and a wall
    /// squeezed to a fifth of its width is a sliver a few pixels across —
    /// contrast there cannot read as flat because there is nothing to read.
    /// Sampled over a full turn, contrast only ever falls below 0.05 while
    /// the narrower wall is under 0.216 of full width; at 0.30 and above the
    /// worst case is 0.082.
    @Test func everyAngleKeepsTheWallsApart() {
        var checked = 0
        for step in 0..<720 {
            let camera = Camera3D(yaw: -.pi + Double(step) / 720 * 2 * .pi)
            guard narrowestWall(from: camera) > 0.30, let contrast = wallContrast(at: camera) else { continue }
            checked += 1
            #expect(contrast > 0.08, "flat at yaw \(camera.yaw)")
        }
        // Just a guard that the foreshortening filter has not thrown the whole
        // orbit away: a shade over half of it clears 0.30.
        #expect(checked > 350)
    }

    /// Turning the plot by a quarter turn shows the same building from an
    /// equivalent angle, so it must be lit the same. This is the property
    /// that makes the orbit feel like one scene rather than four.
    @Test func aQuarterTurnLooksTheSame() {
        for step in 0..<40 {
            let yaw = -.pi + Double(step) / 40 * 2 * .pi
            let here = wallContrast(at: Camera3D(yaw: yaw))
            let there = wallContrast(at: Camera3D(yaw: yaw + .pi / 2))
            guard let here, let there else { continue }
            #expect(abs(here - there) < 1e-9)
        }
    }

    /// A roof is the brightest face of a building, whatever the yaw. It is
    /// the only cue that says which way is up in a projection with no
    /// horizon, so an inverted read — a wall glowing against a dull roof —
    /// would flatten the whole scene.
    @Test func theRoofIsTheBrightestFace() {
        for step in 0..<720 {
            let camera = Camera3D(yaw: -.pi + Double(step) / 720 * 2 * .pi)
            guard narrowestWall(from: camera) > 0.30 else { continue }
            let light = SceneLight.following(camera)
            let sky = light.brightness(normal: SceneLight.up)
            for wall in visibleWalls(from: camera) {
                #expect(light.brightness(normal: wall) < sky)
            }
        }
    }

    /// The exception, stated rather than hidden: the light stands 45° above
    /// the horizon, so a wall turned square-on to it collects marginally more
    /// than a flat roof does. That happens only while the wall is under a
    /// sixteenth of its width — and it is worth at most 0.003 of brightness,
    /// which is less than one step of an 8-bit colour channel. It cannot be
    /// drawn, let alone seen.
    @Test func aWallOutshinesTheRoofOnlyBelowTheResolutionOfTheScreen() {
        let oneColourStep = 1.0 / 255
        for step in 0..<3600 {
            let camera = Camera3D(yaw: -.pi + Double(step) / 3600 * 2 * .pi)
            let light = SceneLight.following(camera)
            let sky = light.brightness(normal: SceneLight.up)
            for wall in visibleWalls(from: camera) {
                #expect(light.brightness(normal: wall) - sky < oneColourStep)
            }
        }
    }

    /// Shadows are cast by the same light that shades the faces, so they
    /// always fall away from the lit side. Two sources would let a wall be
    /// bright while its shadow said it was in shade.
    @Test func shadowsFallAwayFromTheLitSide() {
        for step in 0..<24 {
            let camera = Camera3D(yaw: -.pi + Double(step) / 24 * 2 * .pi)
            let light = SceneLight.following(camera)
            let offset = light.shadowOffset(height: 3)
            #expect(offset.x * light.toSun.x + offset.y * light.toSun.y < 0)
            // Three metres up throws a shadow of a sane length, not a
            // kilometre: the light never lies down flat.
            #expect((offset.x * offset.x + offset.y * offset.y).squareRoot() < 12)
        }
    }

    /// Brightness is a direction, not a magnitude: a normal scaled by ten is
    /// the same face. `roofNormal` returns unnormalised vectors, so this is
    /// load-bearing rather than pedantry.
    @Test func brightnessIgnoresTheLengthOfTheNormal() {
        let light = SceneLight.following(Camera3D(yaw: 0.7))
        let normal = (x: 0.3, y: -0.8, z: 2.0)
        let scaled = (x: normal.x * 17, y: normal.y * 17, z: normal.z * 17)
        #expect(abs(light.brightness(normal: normal) - light.brightness(normal: scaled)) < 1e-12)
        #expect(light.brightness(normal: (x: 0, y: 0, z: 0)) > 0)
    }

    /// A wall's normal points out of the building whichever way round the
    /// caller listed the edge — the fault that put every second roof slope's
    /// overhang inside the wall and lit it as if it faced the sun.
    @Test func wallNormalsPointOutOfTheFootprint() {
        let centre = Point(x: 4, y: -2)
        let corners = [
            Point(x: 1, y: -5), Point(x: 7, y: -5), Point(x: 7, y: 1), Point(x: 1, y: 1)
        ]
        for index in 0..<4 {
            let a = corners[index]
            let b = corners[(index + 1) % 4]
            for (from, to) in [(a, b), (b, a)] {
                let normal = SceneLight.wallNormal(from: from, to: to, about: centre)
                let midX = (from.x + to.x) / 2 - centre.x
                let midY = (from.y + to.y) / 2 - centre.y
                #expect(normal.x * midX + normal.y * midY > 0)
            }
        }
    }
}
