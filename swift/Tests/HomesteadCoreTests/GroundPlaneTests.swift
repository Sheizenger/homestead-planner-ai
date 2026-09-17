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
