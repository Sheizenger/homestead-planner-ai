import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

/// The scene is built here and rendered somewhere this cannot reach, so every
/// question that can be answered without a GPU is answered here.
struct SceneBuilderTests {
    private func plot(water: Waterfront? = nil) -> Plot {
        Plot(
            boundary: [
                Point(x: 0, y: 0), Point(x: 52, y: 0),
                Point(x: 52, y: 40), Point(x: 0, y: 40),
            ],
            waterfront: water
        )
    }

    private func object(_ typeId: String, _ x: Double, _ y: Double, _ w: Double, _ d: Double, rotation: Double = 0) -> PlanObject {
        PlanObject(
            id: typeId + "-1",
            typeId: typeId,
            category: .residential,
            transform: Transform(x: x, y: y, width: w, height: d, rotationDeg: rotation),
            label: typeId,
            layerId: .residential
        )
    }

    private func variant(_ objects: [PlanObject], fences: [Fence] = [], paths: [PathEntity] = []) -> Variant {
        Variant(
            strategyLabel: "test", mode: .beautyBalanced, seed: 1, zones: [],
            objects: objects, paths: paths, fences: fences, utilityNodes: [],
            generatedFromBrief: Brief(structuredInputs: StructuredInputs()),
            generatedFromPlotBoundary: [],
            analyticsSnapshot: AnalyticsSnapshot(
                totalAreaM2: 0, allocatedAreaM2: 0, unallocatedAreaM2: 0, byCategory: [],
                estimatedFoodProductionScore: 0, maintenanceComplexityScore: 0
            ),
            warningsSnapshot: []
        )
    }

    // MARK: - Buildings

    /// A building has to come out the size the plan says it is. Everything
    /// else in a planning tool is decoration.
    @Test func aBuildingFillsItsFootprint() {
        for (width, depth) in [(12.0, 10.0), (4.0, 3.0), (18.0, 5.0), (3.0, 14.0)] {
            let objects = [object("house", 20, 20, width, depth)]
            var scene = Scene3D()
            for item in objects { SceneBuilder.place(item, into: &scene, metrics: ModelMetrics.all) }
            let bays = scene.meshes.filter { $0.model.hasPrefix("city/") }
            #expect(!bays.isEmpty, "\(width)x\(depth) produced no building")

            var minX = Double.infinity, maxX = -Double.infinity
            var minY = Double.infinity, maxY = -Double.infinity
            for bay in bays {
                guard let bounds = ModelMetrics[bay.model] else { continue }
                let size = bay.size(from: bounds)
                guard let centre = ModelPlacement.footprintCentre(of: bay) else { continue }
                // The mesh may be turned a quarter, which swaps its extents.
                let turned = abs(abs(bay.yaw).truncatingRemainder(dividingBy: .pi) - .pi / 2) < 0.01
                let halfX = (turned ? size.depth : size.width) / 2
                let halfY = (turned ? size.width : size.depth) / 2
                minX = min(minX, centre.x - halfX); maxX = max(maxX, centre.x + halfX)
                minY = min(minY, centre.y - halfY); maxY = max(maxY, centre.y + halfY)
            }
            #expect(abs((maxX - minX) - width) < 0.05, "\(width)x\(depth) came out \(maxX - minX) wide")
            #expect(abs((maxY - minY) - depth) < 0.05, "\(width)x\(depth) came out \(maxY - minY) deep")
        }
    }

    /// The reason bays exist. A mesh is about as wide as it is deep, so a long
    /// thin building stretched from one is a smeared building; split into
    /// bays, no piece is stretched far.
    @Test func aLongBuildingIsSplitIntoBaysRatherThanSmeared() {
        let long = SceneBuilder.chooseBuilding(
            meshes: SceneCatalog.workingMeshes, width: 24, depth: 5, seed: "x"
        )
        #expect(long != nil)
        #expect(long!.bays > 1, "a 24 x 5 building should be more than one bay")
        #expect(long!.distortion < 1.6)

        let square = SceneBuilder.chooseBuilding(
            meshes: SceneCatalog.workingMeshes, width: 8, depth: 7, seed: "x"
        )
        #expect(square?.bays == 1, "a square building should not be chopped up")
    }

    /// The complaint this is here to prevent: five small outbuildings on one
    /// plot all choosing the closest-fitting mesh and coming out identical.
    @Test func buildingsOfTheSameSizeAreNotAllTheSameBuilding() {
        let chosen = (0..<8).compactMap {
            SceneBuilder.chooseBuilding(
                meshes: SceneCatalog.outbuildingMeshes, width: 4, depth: 5, seed: "shed-\($0)"
            )?.model
        }
        #expect(Set(chosen).count >= 3, "eight sheds used \(Set(chosen).count) meshes")
    }

    /// And the bound on that freedom: variety is bought within a tolerance,
    /// not at any price.
    @Test func varietyNeverCostsMoreThanTheTolerance() {
        for (width, depth) in [(4.0, 5.0), (12.0, 10.0), (20.0, 6.0), (3.0, 3.0)] {
            let options = SceneBuilder.buildingOptions(
                meshes: SceneCatalog.houseMeshes, width: width, depth: depth
            )
            guard let best = options.first else { continue }
            for seed in 0..<12 {
                let choice = SceneBuilder.chooseBuilding(
                    meshes: SceneCatalog.houseMeshes, width: width, depth: depth, seed: "s\(seed)"
                )
                #expect(choice != nil)
                #expect(choice!.distortion <= best.distortion * SceneBuilder.fitTolerance + 1e-9)
            }
        }
    }

    /// Height follows the mesh rather than being dictated to it — the fault
    /// that turned a 12 x 10 house into a nine-metre windowless block.
    @Test func aBuildingKeepsItsOwnProportions() {
        for (width, depth) in [(12.0, 10.0), (5.0, 4.0), (16.0, 6.0)] {
            var scene = Scene3D()
            SceneBuilder.place(object("house", 20, 20, width, depth), into: &scene, metrics: ModelMetrics.all)
            guard let bay = scene.meshes.first(where: { $0.model.hasPrefix("city/") }),
                  let bounds = ModelMetrics[bay.model] else { Issue.record("no building"); return }
            let size = bay.size(from: bounds)
            let nativeRatio = bounds.height / max(bounds.width, bounds.depth)
            let builtRatio = size.height / max(size.width, size.depth)
            // Within half again of its own proportions, which is what the
            // clamp on the catalog height allows.
            #expect(builtRatio > nativeRatio * 0.45 && builtRatio < nativeRatio * 1.9,
                    "\(width)x\(depth): native \(nativeRatio), built \(builtRatio)")
        }
    }

    /// Nothing hovers and nothing is buried. `town/watermill` is modelled with
    /// its origin nearly a unit above its base, so this is not theoretical.
    @Test func everythingStandsOnTheGround() {
        var scene = Scene3D()
        for typeId in SceneCatalog.table.keys.sorted() {
            SceneBuilder.place(object(typeId, 20, 20, 6, 5), into: &scene, metrics: ModelMetrics.all)
        }
        #expect(scene.meshes.count > 30)
        for node in scene.meshes {
            guard let bounds = ModelMetrics[node.model] else { continue }
            guard node.pitch == 0 else { continue }   // a tilted panel stands on legs
            let lowest = node.position.y + bounds.minY * node.scale.y
            #expect(abs(lowest) < 0.01, "\(node.model) sits at \(lowest)")
        }
    }

    // MARK: - The site

    /// The bug that hid the river: ground drawn across the whole plot, water
    /// below it, and in a renderer with a depth buffer the lawn wins.
    @Test func theGroundStopsAtTheWater() {
        let wet = plot(water: Waterfront(type: .river, edge: .north, widthM: 11))
        var scene = Scene3D()
        SceneBuilder.ground(wet, into: &scene)
        guard let ground = scene.slabs.first else { Issue.record("no ground"); return }
        for point in ground.polygon {
            #expect(point.y >= 11 - 1e-6, "the lawn reaches \(point.y), into the river")
        }
        // And a dry plot keeps the whole thing.
        var dry = Scene3D()
        SceneBuilder.ground(plot(), into: &dry)
        #expect(dry.slabs.first?.polygon.count == 4)
    }

    /// The same fault one layer down: a bank across the whole strip is an
    /// opaque lid over the water it is supposed to sit beside.
    @Test func theBankIsOnlyTheDryPart() {
        for type in WaterfrontType.allCases {
            let wet = plot(water: Waterfront(type: type, edge: .north, widthM: 11))
            guard let bank = WaterfrontModel.bank(of: wet),
                  let shore = WaterfrontModel.shoreline(of: wet) else { Issue.record("no bank"); return }
            #expect(bank.count > 3)
            // Every bank point is on the landward side of the deepest water.
            let deepest = shore.map(\.y).min() ?? 0
            for point in bank { #expect(point.y > deepest) }
            // And the bank reaches the planning line, or the lawn would float.
            #expect(bank.contains { abs($0.y - 11) < 1e-6 })
        }
    }

    @Test func aWholeSceneComesOutOfAWholePlan() {
        let wet = plot(water: Waterfront(type: .lake, edge: .west, widthM: 9))
        let objects = ["house", "barn", "greenhouse", "orchard-trees", "pool", "dock", "well"]
            .enumerated()
            .map { object($0.element, 20 + Double($0.offset) * 4, 20, 6, 5) }
        let scene = SceneBuilder.build(plot: wet, variant: variant(objects))
        #expect(scene.meshes.count > 10)
        #expect(scene.slabs.contains { $0.id == "ground" })
        #expect(scene.slabs.contains { $0.id == "waterfront" })
        #expect(scene.solids.contains { $0.id.hasPrefix("greenhouse") })
        // Every node's id is unique, or the renderer's cache collides and
        // half the plot shares one transform.
        let ids = scene.meshes.map(\.id)
        #expect(Set(ids).count == ids.count)
        for node in scene.meshes {
            #expect(node.position.x.isFinite && node.position.y.isFinite && node.position.z.isFinite)
            #expect(node.scale.x > 0 && node.scale.y > 0 && node.scale.z > 0)
        }
    }

    /// A fence follows its line: panels end to end, the right way round, and
    /// no gaps. Drawn wrong this is the "fences walk through buildings"
    /// complaint all over again.
    @Test func fencePanelsFollowTheirLine() {
        let line = Fence(id: "f", points: [Point(x: 0, y: 0), Point(x: 12, y: 0), Point(x: 12, y: 9)], fenceType: .perimeter, gated: false)
        var scene = Scene3D()
        SceneBuilder.fences(variant([], fences: [line]), into: &scene, metrics: ModelMetrics.all)
        #expect(scene.meshes.count >= 8)
        guard let bounds = ModelMetrics[SceneBuilder.fenceMesh] else { Issue.record("no fence mesh"); return }
        for node in scene.meshes {
            let along = bounds.depth * node.scale.z
            #expect(along > 1.0 && along < 4.0, "a \(along) m fence panel")
            let height = bounds.height * node.scale.y
            #expect(abs(height - SceneBuilder.fenceHeight) < 0.01)
            // On the line, not beside it.
            let onFirstLeg = abs(node.position.z) < 0.6 && node.position.x > -0.6 && node.position.x < 12.6
            let onSecondLeg = abs(node.position.x - 12) < 0.6 && node.position.z > -0.6 && node.position.z < 9.6
            #expect(onFirstLeg || onSecondLeg, "panel at \(node.position.x), \(node.position.z)")
        }
    }

    @Test func anEmptyPlanStillProducesGroundAndNothingElse() {
        let scene = SceneBuilder.build(plot: plot(), variant: variant([]))
        #expect(scene.meshes.isEmpty)
        #expect(scene.slabs.count == 1)
        #expect(!scene.isEmpty)
    }
}
