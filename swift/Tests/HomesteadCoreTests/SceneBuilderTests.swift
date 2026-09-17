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
        SceneBuilder.fences(variant([], fences: [line]), plot(), into: &scene, metrics: ModelMetrics.all)
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

    /// A plot with nothing on it is still a field, not a green rectangle.
    // MARK: - Nothing inside anything else

    /// The fault the whole of this file exists for, and the one anybody looking
    /// at the plan sees first: a tractor halfway into the barn wall.
    ///
    /// It came from reading a prop's offset as a fraction of the half-extent,
    /// which puts every value under 1.0 inside the footprint. Twelve of the
    /// sixteen faults in the first scene with meshes were this one.
    @Test func propsStandBesideTheirObjectAndNotInIt() {
        for typeId in ["barn", "garage", "workshop", "house", "woodshed"] {
            let item = object(typeId, 30, 30, 10, 8)
            var taken: [(centre: Point, radius: Double)] = []
            let props = SceneBuilder.props(
                item, look: SceneCatalog.look(for: item), clearOf: &taken, metrics: ModelMetrics.all
            )
            #expect(!props.isEmpty, "\(typeId) drew no props")
            for prop in props {
                guard let centre = ModelPlacement.footprintCentre(of: prop) else { continue }
                #expect(!Polygon.contains(centre, polygon: item.transform.corners),
                        "\(typeId): its \(prop.model) stands inside it")
            }
        }
    }

    /// And the other way about: what belongs to a *place* rather than a
    /// building stands on it. Pushing everything outside emptied the paddock.
    @Test func whatBelongsToAPlaceStandsOnIt() {
        for typeId in ["goat-paddock", "patio", "apiary"] {
            let item = object(typeId, 30, 30, 12, 10)
            let look = SceneCatalog.look(for: item)
            var taken: [(centre: Point, radius: Double)] = []
            let props = SceneBuilder.props(
                item, look: look, clearOf: &taken,
                inside: SceneBuilder.propsStandOnTheirObject(look), metrics: ModelMetrics.all
            )
            #expect(!props.isEmpty, "\(typeId) drew no props")
            for prop in props {
                guard let centre = ModelPlacement.footprintCentre(of: prop) else { continue }
                #expect(Polygon.contains(centre, polygon: item.transform.corners),
                        "\(typeId): its \(prop.model) wandered off it")
            }
        }
    }

    /// A prop pushed out of its own building must not land in the next one.
    @Test func aPropWalksRoundToASideThatIsFree() {
        let barn = object("barn", 20, 20, 10, 8)
        // Boxed in on the obvious side.
        let blocker = object("shed", 20, 30, 12, 8)
        var taken: [(centre: Point, radius: Double)] = []
        let props = SceneBuilder.props(
            barn, look: SceneCatalog.look(for: barn),
            avoiding: [blocker.transform.corners], clearOf: &taken, metrics: ModelMetrics.all
        )
        for prop in props {
            guard let centre = ModelPlacement.footprintCentre(of: prop) else { continue }
            #expect(!Polygon.contains(centre, polygon: blocker.transform.corners),
                    "\(prop.model) was pushed into the shed")
        }
    }

    /// Two objects' props must not be pushed onto the same patch of grass.
    /// Placed one object at a time, the garage's car and the woodshed's log
    /// pile were both shoved out of their own buildings and into each other.
    @Test func propsOfDifferentObjectsKeepOutOfEachOther() {
        let garage = object("garage", 30, 30, 6, 6)
        let woodshed = object("woodshed", 36, 30, 3, 4)
        let scene = SceneBuilder.build(plot: plot(), variant: variant([garage, woodshed]))
        let props = scene.meshes.filter { $0.id.contains("prop") }
        #expect(props.count >= 2)
        for i in props.indices {
            for j in props.indices where j > i {
                guard props[i].objectId != props[j].objectId,
                      let a = ModelMetrics[props[i].model], let b = ModelMetrics[props[j].model],
                      let pa = ModelPlacement.footprintCentre(of: props[i]),
                      let pb = ModelPlacement.footprintCentre(of: props[j]) else { continue }
                let radii = (max(a.width * props[i].scale.x, a.depth * props[i].scale.z)
                    + max(b.width * props[j].scale.x, b.depth * props[j].scale.z)) / 2
                let gap = ((pa.x - pb.x) * (pa.x - pb.x) + (pa.y - pb.y) * (pa.y - pb.y)).squareRoot()
                #expect(gap > radii * 0.75,
                        "\(props[i].model) and \(props[j].model) are \(gap) m apart")
            }
        }
    }

    /// A solar array is placed *inside* the house's footprint on purpose,
    /// because it goes on the roof. A builder that does not know that lays it
    /// on the lawn under the house — one building through another.
    @Test func aRoofMountedThingSitsOnTheRoof() {
        var house = object("house", 30, 30, 12, 10)
        house.id = "the-house"
        var array = object("solar-array", 30, 29, 8, 5)
        array.id = "the-array"
        array.metadata["roofMounted"] = .bool(true)

        let ground = SceneBuilder.baseElevation(
            of: house, among: [house, array], metrics: ModelMetrics.all
        )
        #expect(ground == 0, "the house should stand on the ground")

        let roof = SceneBuilder.baseElevation(
            of: array, among: [house, array], metrics: ModelMetrics.all
        )
        guard let height = SceneBuilder.buildingHeight(of: house, metrics: ModelMetrics.all) else {
            Issue.record("no height for the house"); return
        }
        // On the roof, and clear of everything under it.
        //
        // Something laid flat across a pitched roof has to clear the highest
        // point beneath it, so an array spanning the ridge seats at ridge
        // height. That is a little proud of the slopes and it is the right
        // side to err on: the alternative is a rectangle sunk into the tiles,
        // which reads as a hole cut in the roof.
        #expect(roof > height * 0.45, "the array is at \(roof) on a \(height) m house")
        #expect(roof <= height + SceneBuilder.roofLift + 0.01, "the array floats above the house")
    }

    /// Roof panels lie flat. A lean on top of a seat computed from the roof's
    /// own profile lifted them clean over it.
    @Test func roofPanelsDoNotAlsoLean() {
        var array = object("solar-array", 30, 30, 8, 5)
        array.id = "array"
        var scene = Scene3D()
        SceneBuilder.place(array, into: &scene, base: 6, metrics: ModelMetrics.all)
        #expect(!scene.meshes.isEmpty)
        #expect(scene.meshes.allSatisfy { $0.pitch == 0 })

        var onTheGround = Scene3D()
        SceneBuilder.place(array, into: &onTheGround, base: 0, metrics: ModelMetrics.all)
        #expect(onTheGround.meshes.contains { $0.pitch != 0 }, "a ground array should lean")
    }

    /// The measurement roof-mounting rests on: how high a mesh stands over
    /// each patch of its own footprint. A bounding box cannot say *where* the
    /// nine metres is, and that is the whole question.
    @Test func everyBuildingMeshKnowsHowHighItIsAtEachPoint() {
        for name in SceneCatalog.houseMeshes + SceneCatalog.workingMeshes {
            guard let bounds = ModelMetrics[name] else { Issue.record("no \(name)"); continue }
            #expect(bounds.surface.count == 36, "\(name) has no surface map")
            #expect(bounds.surface.allSatisfy { $0 >= 0 && $0 <= 1.0001 })
            // Something reaches full height somewhere — the ridge.
            #expect(bounds.surface.max()! > 0.9, "\(name) never reaches its own top")
            // It varies: a building is not a slab, and a map that says one
            // height everywhere is a map that was not measured.
            #expect(bounds.surface.min()! < bounds.surface.max()! * 0.9,
                    "\(name) reads as the same height everywhere")
            // And asking about a patch gives the highest thing on it, which
            // is the whole point: something laid there has to clear it.
            let whole = bounds.top(from: 0, 0, to: 1, 1) ?? 0
            #expect(abs(whole - bounds.surface.max()!) < 1e-9)
        }
    }

    @Test func anEmptyPlanIsGroundAndWhatGrowsOnIt() {
        let scene = SceneBuilder.build(plot: plot(), variant: variant([]))
        #expect(scene.slabs.count == 1)
        #expect(scene.meshes.count > 20, "an empty plot came out bare")
        #expect(scene.meshes.allSatisfy { $0.id.hasPrefix("wild-") })
        #expect(scene.meshes.allSatisfy { $0.objectId == nil }, "undergrowth is not selectable")
    }

    /// And nothing grows through anything. `Polygon.clearance` answers
    /// `.infinity` for a single point, so the first version of this filter
    /// excluded nothing at all and put wild trees inside the barn.
    @Test func nothingWildGrowsThroughWhatWasBuilt() {
        let objects = [
            object("house", 20, 20, 12, 10),
            object("barn", 36, 26, 10, 8),
            object("goat-paddock", 10, 30, 14, 10),
        ]
        let scene = SceneBuilder.build(plot: plot(), variant: variant(objects))
        let wild = scene.meshes.filter { $0.id.hasPrefix("wild-") }
        #expect(!wild.isEmpty)
        for node in wild {
            let point = Point(x: node.position.x, y: node.position.z)
            for item in objects {
                #expect(!Polygon.contains(point, polygon: item.transform.corners),
                        "\(node.model) is inside the \(item.typeId)")
            }
        }
    }
}
