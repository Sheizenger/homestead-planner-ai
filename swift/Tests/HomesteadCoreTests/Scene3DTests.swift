import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

/// Placing a mesh is three separate ways to be wrong, and the renderer cannot
/// be run here to show any of them. So they are pinned instead.
struct Scene3DTests {
    /// A mesh whose origin is nowhere near its own centre or its own base —
    /// which is not a contrived case: `town/watermill` sits 0.9 units above
    /// its lowest point, because it is modelled to stand in water.
    private let awkward = ModelBounds(
        minX: -3, maxX: 1,      // centre at −1, not 0
        minY: -0.9, maxY: 2.1,  // origin 0.9 above the base
        minZ: 0, maxZ: 2        // centre at +1
    )
    private var metrics: [String: ModelBounds] { ["kit/awkward": awkward, "kit/cube": cube] }
    private let cube = ModelBounds(minX: -0.5, maxX: 0.5, minY: 0, maxY: 1, minZ: -0.5, maxZ: 0.5)

    // MARK: - Fitting

    @Test func aFootprintFitFillsExactlyTheSpaceThePlanGaveIt() {
        let scale = ModelPlacement.scale(
            for: .footprint(height: 6), bounds: awkward, footprint: Size(width: 12, height: 8)
        )
        #expect(abs(awkward.width * scale.x - 12) < 1e-12)
        #expect(abs(awkward.depth * scale.z - 8) < 1e-12)
        #expect(abs(awkward.height * scale.y - 6) < 1e-12)
    }

    /// The one that matters for anything with a shape: a tree scaled to fit a
    /// long thin bed must stay a tree.
    @Test func aStandingFitNeverDistorts() {
        for footprint in [Size(width: 1, height: 20), Size(width: 30, height: 2)] {
            let scale = ModelPlacement.scale(for: .standing(height: 5), bounds: awkward, footprint: footprint)
            #expect(scale.x == scale.y)
            #expect(scale.y == scale.z)
            #expect(abs(awkward.height * scale.y - 5) < 1e-12)
        }
    }

    @Test func aSpanningFitSizesByGroundCoverAndAnInscribedOneStaysInside() {
        let spanning = ModelPlacement.scale(for: .spanning(2), bounds: awkward, footprint: Size(width: 99, height: 99))
        #expect(abs(awkward.span * spanning.x - 2) < 1e-12)
        #expect(spanning.x == spanning.z)

        let inscribed = ModelPlacement.scale(for: .inscribed, bounds: awkward, footprint: Size(width: 12, height: 4))
        #expect(awkward.width * inscribed.x <= 12 + 1e-12)
        #expect(awkward.depth * inscribed.z <= 4 + 1e-12)
        #expect(inscribed.x == inscribed.z)
    }

    @Test func aDegenerateMeshOrFootprintDoesNotProduceInfinity() {
        let flat = ModelBounds(minX: 0, maxX: 0, minY: 0, maxY: 0, minZ: 0, maxZ: 0)
        for fit in [ModelFit.footprint(height: 3), .standing(height: 3), .spanning(3), .inscribed] {
            let scale = ModelPlacement.scale(for: fit, bounds: flat, footprint: Size(width: 0, height: 0))
            #expect(scale.x.isFinite && scale.y.isFinite && scale.z.isFinite)
            #expect(scale.x > 0 && scale.y > 0 && scale.z > 0)
        }
    }

    // MARK: - Placing

    @Test func aMeshLandsCentredOnItsFootprintWhateverItsOriginIs() {
        let node = ModelPlacement.node(
            id: "n", model: "kit/awkward", centre: Point(x: 30, y: -12),
            fit: .standing(height: 4), metrics: metrics
        )
        guard let node, let centre = ModelPlacement.footprintCentre(of: node, metrics: metrics) else {
            Issue.record("no node"); return
        }
        #expect(abs(centre.x - 30) < 1e-12)
        #expect(abs(centre.y + 12) < 1e-12)
    }

    /// The bug this exists to prevent: rotate about the origin instead of the
    /// footprint and a mesh whose origin is off-centre swings away from where
    /// the plan put it — further the more it is turned.
    @Test func aTurnedMeshStaysWhereThePlanPutIt() {
        for degrees in stride(from: 0.0, to: 360.0, by: 15) {
            guard let node = ModelPlacement.node(
                id: "n", model: "kit/awkward", centre: Point(x: 5, y: 7),
                yaw: degrees * .pi / 180, fit: .standing(height: 3), metrics: metrics
            ), let centre = ModelPlacement.footprintCentre(of: node, metrics: metrics) else {
                Issue.record("no node"); return
            }
            #expect(abs(centre.x - 5) < 1e-9, "drifted at \(degrees)°")
            #expect(abs(centre.y - 7) < 1e-9, "drifted at \(degrees)°")
        }
    }

    /// And the other one: a mesh modelled with its origin above its base
    /// floats, and one modelled below it sinks into the ground.
    @Test func aMeshStandsOnTheGroundAndNotInIt() {
        for (model, bounds) in metrics {
            for base in [0.0, 1.5] {
                guard let node = ModelPlacement.node(
                    id: "n", model: model, centre: Point(x: 0, y: 0), base: base,
                    fit: .standing(height: 2), metrics: metrics
                ) else { Issue.record("no node"); return }
                let lowest = node.position.y + bounds.minY * node.scale.y
                #expect(abs(lowest - base) < 1e-12, "\(model) does not sit on \(base)")
            }
        }
    }

    @Test func anUnknownMeshIsNoNodeRatherThanAWrongOne() {
        #expect(ModelPlacement.node(
            id: "n", model: "kit/nothing", centre: Point(x: 0, y: 0), fit: .inscribed, metrics: metrics
        ) == nil)
    }

    // MARK: - Axes

    /// The engine's plan view is X-east, Y-south, Z-up; the scene is X-east,
    /// Y-up, Z-south. Getting this backwards mirrors the whole site, which is
    /// the kind of thing that looks almost right.
    @Test func theGroundPlaneMapsStraightAcross() {
        let plan = Point(x: 12, y: -4)
        let lifted = Vector3.ground(plan, height: 3)
        #expect(lifted.x == 12)
        #expect(lifted.y == 3)
        #expect(lifted.z == -4)
        #expect(lifted.plan == plan)
    }

    /// Swapping two axes reverses the handedness, so the engine's
    /// anticlockwise turn is clockwise in the scene. One negation, here.
    @Test func aTurnInThePlanIsTheSameTurnInTheScene() {
        // A point due east of the centre, turned 90° in the engine's plan,
        // ends up due south — increasing Y.
        let engineDegrees = 90.0
        let turned = Transform(x: 0, y: 0, width: 2, height: 2, rotationDeg: engineDegrees)
        let corner = turned.corners[1]                       // was (+1, −1)
        #expect(abs(corner.x - 1) < 1e-9 && abs(corner.y - 1) < 1e-9)

        // The same turn in the scene has to take the same mesh corner to the
        // same place: engine +Y is scene +Z.
        let yaw = sceneYaw(fromEngineDegrees: engineDegrees)
        let start = Vector3(x: 1, y: 0, z: -1)
        let ended = Vector3(
            x: start.x * cos(yaw) + start.z * sin(yaw),
            y: 0,
            z: -start.x * sin(yaw) + start.z * cos(yaw)
        )
        #expect(abs(ended.x - corner.x) < 1e-9)
        #expect(abs(ended.z - corner.y) < 1e-9)
    }

    // MARK: - The real table

    @Test func everyVendoredMeshWasMeasured() {
        #expect(ModelMetrics.all.count > 350)
        for (name, bounds) in ModelMetrics.all {
            #expect(name.contains("/"), "\(name) is not kit/name")
            #expect(bounds.width >= 0 && bounds.height >= 0 && bounds.depth >= 0)
            // Nothing in these kits is a point or a kilometre across; a mesh
            // that measured as either means the OBJ was misread.
            #expect(bounds.span > 0.001 && bounds.span < 100, "\(name) spans \(bounds.span)")
        }
    }

    /// Spot checks against the kits, so a regenerated table that silently
    /// changed shape is caught. `town/wall` being a 1x1 panel is what makes
    /// modular assembly possible at all.
    @Test func theKitsAreTheShapeTheRestOfThisAssumes() {
        guard let wall = ModelMetrics["town/wall"],
              let watermill = ModelMetrics["town/watermill"],
              let tree = ModelMetrics["forest/tree"] else { Issue.record("table is missing meshes"); return }
        #expect(abs(wall.depth - 1) < 0.02)
        #expect(abs(wall.height - 1) < 0.02)
        #expect(wall.width < 0.2, "a wall panel should be thin")

        // Modelled standing in water, 0.9 units below its own origin.
        #expect(watermill.baseOffset > 0.5)
        // And one modelled the ordinary way, for contrast.
        #expect(abs(tree.baseOffset) < 0.01)
    }
}
