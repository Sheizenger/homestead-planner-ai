import Foundation
import Testing
import HomesteadEngine
@testable import HomesteadCore

struct GroundPlaneTests {
    /// The one that matters: a slab and a mesh at the same plan point must
    /// end up at the same place. They did not, and the ground was drawn a
    /// plot's depth away from everything standing on it.
    @Test func aSlabLandsWhereAMeshAtTheSamePlanPointStands() {
        for point in [Point(x: 0, y: 0), Point(x: 24.7, y: 32), Point(x: 52, y: 40), Point(x: -3, y: 11.5)] {
            let slab = GroundPlane.scenePoint(point)
            // How `ModelPlacement` puts a mesh on the ground: plan y is scene z.
            let mesh = Vector3(x: point.x, y: 0, z: point.y)
            #expect(slab == mesh, "slab \(slab) but mesh \(mesh) for \(point)")
        }
    }

    /// `laidDown` claims to be a quarter turn about X. Check it against the
    /// rotation itself rather than against a copy of its own arithmetic.
    @Test func layingDownIsTheQuarterTurnItSaysItIs() {
        let angle = GroundPlane.pitch
        for point in [Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 7.5, y: -2.25)] {
            let turned = GroundPlane.laidDown(point)
            // (x, y, 0) about X: y' = y·cos − z·sin, z' = y·sin + z·cos.
            let y = point.y * cos(angle)
            let z = point.y * sin(angle)
            #expect(abs(turned.x - point.x) < 1e-12)
            #expect(abs(turned.y - y) < 1e-12)
            #expect(abs(turned.z - z) < 1e-12)
        }
    }

    /// Mirroring a polygon turns it inside out, which decides which way its
    /// faces point. Reversing it turns it back.
    @Test func thePathWindsTheWayThePolygonDid() {
        let square = [
            Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 3), Point(x: 0, y: 3),
        ]
        func turn(_ points: [Point]) -> Double {
            var sum = 0.0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                sum += a.x * b.y - b.x * a.y
            }
            return sum
        }
        let path = GroundPlane.path(square)
        #expect(turn(path).sign == turn(square).sign)
        #expect(Polygon.area(path) == Polygon.area(square))
    }

    /// The trip preserves shape: a slab is not stretched or sheared by being
    /// laid down, only moved.
    @Test func layingASlabDownDoesNotResizeIt() {
        let plot = [
            Point(x: 0, y: 11), Point(x: 52, y: 11), Point(x: 52, y: 40), Point(x: 0, y: 40),
        ]
        let laid = GroundPlane.path(plot).map(GroundPlane.laidDown)
        let xs = laid.map(\.x), zs = laid.map(\.z)
        #expect(xs.min() == 0 && xs.max() == 52)
        #expect(zs.min() == 11 && zs.max() == 40)
    }
}

struct SlabDepthTests {
    /// The one the user saw: a mesh stands on the plane the plan puts it on,
    /// and the ground's top face has to be that same plane. It was 0.8m
    /// above it, so everything on the plot stood buried to the knee.
    @Test func theGroundsSurfaceIsTheHeightMeshesStandOn() {
        let thickness = 1.6, top = 0.0
        let centre = GroundPlane.centre(top: top, thickness: thickness)
        let surface = centre + GroundPlane.extrusion(thickness) / 2
        #expect(abs(surface - top) < 1e-12, "surface \(surface), meshes stand on \(top)")
    }

    /// A slab hangs below the height it names, never above it.
    @Test func aSlabHangsBelowItsTop() {
        for (top, thickness) in [(0.0, 1.6), (0.06, 0.0), (0.2, 0.2), (-0.35, 1.4)] {
            let centre = GroundPlane.centre(top: top, thickness: thickness)
            let half = GroundPlane.extrusion(thickness) / 2
            #expect(abs((centre + half) - top) < 1e-12)
            #expect(centre - half <= top + 1e-12)
        }
    }

    /// A built volume's walls stand on their base and stop at their height.
    /// They were floating half a storey up, which is why a greenhouse had no
    /// bottom to it.
    @Test func wallsStandOnTheirBase() {
        for (base, wallHeight) in [(0.0, 1.2), (0.0, 1.9), (0.4, 2.5)] {
            let centre = GroundPlane.centre(top: base + wallHeight, thickness: wallHeight)
            let half = GroundPlane.extrusion(wallHeight) / 2
            #expect(abs((centre - half) - base) < 1e-12, "foot at \(centre - half), base \(base)")
            #expect(abs((centre + half) - (base + wallHeight)) < 1e-12)
        }
    }
}
