import Testing
@testable import HomesteadEngine

/// Rules the frozen web app lacks, and the two measurements that justify them.
struct PlanningRulesTests {
    private func plot() -> Plot {
        Plot(
            boundary: PlotShape.rectangle(width: 80, height: 60),
            waterfront: Waterfront(type: .river, edge: .north, widthM: 10, flowSpeedMps: 1.2, elevationDropM: 2)
        )
    }

    private func brief() -> Brief {
        var inputs = StructuredInputs()
        inputs.householdSize = 4
        inputs.infrastructure = ["pool", "well", "septic", "workshop"]
        inputs.animals = [AnimalRequest(type: "goats", count: 6), AnimalRequest(type: "poultry", count: 20)]
        inputs.crops = ["vegetables", "berries"]
        return Brief(structuredInputs: inputs)
    }

    /// You do not fence a river: the water is the boundary. The perimeter used
    /// to be the boundary polygon verbatim, so on a riverside plot two of its
    /// four corners sat out in the water.
    @Test func thePerimeterStopsAtTheWater() {
        let plot = self.plot()
        let water = try! #require(WaterfrontModel.bounds(of: plot))
        let layout = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: 3)

        for fence in layout.fences where fence.fenceType == .perimeter {
            for point in fence.points {
                let inside = point.x >= water.minX && point.x <= water.maxX
                    && point.y >= water.minY && point.y <= water.maxY
                #expect(!inside, Comment(rawValue: "\(fence.id) has a post at \(point)"))
            }
        }

        // And the frozen reading still runs the fence all the way round, which
        // is what the golden fixtures record.
        let frozen = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: 3, policy: .frozen)
        let perimeter = frozen.fences.first { $0.fenceType == .perimeter }
        #expect(perimeter?.points.count == plot.boundary.count)
    }

    /// A pool at the bottom of the garden by the goats is the complaint this
    /// came from. Stated as a comparison, because the absolute distance
    /// depends on how full the plot is: the corrected rulebook has to put it
    /// nearer the house than the frozen one does, on every seed.
    @Test func theCorrectedRulebookKeepsThePoolNearerTheHouse() {
        var correctedTotal = 0.0
        var frozenTotal = 0.0
        var measured = 0

        for seed in 1...8 {
            func distanceToHouse(_ policy: Constraints.SeparationPolicy) -> Double? {
                let layout = Generate.variant(plot: plot(), brief: brief(), mode: .beautyBalanced, seed: seed, policy: policy)
                guard let pool = layout.objects.first(where: { $0.typeId == "pool" }),
                      let house = layout.objects.first(where: { ObjectLibrary.houseTypeIDs.contains($0.typeId) })
                else { return nil }
                return Polygon.clearance(pool.transform.corners, house.transform.corners)
            }
            guard let corrected = distanceToHouse(.corrected), let frozen = distanceToHouse(.frozen) else { continue }
            correctedTotal += corrected
            frozenTotal += frozen
            measured += 1
        }

        #expect(measured >= 6)
        #expect(correctedTotal < frozenTotal)
    }

    /// The pull has to be superlinear for the same reason the separation
    /// penalty is: flat, it loses every argument with a separation and things
    /// that belong together end up scattered.
    @Test func adjacencyIsWeighedBySeverityNotJustDistance() {
        let adjacency = Constraints.all(for: .generic, policy: .corrected).filter { $0.kind == .adjacency }
        #expect(adjacency.contains { $0.id == "pool-house-adjacency" })
        #expect(!Constraints.all(for: .generic, policy: .frozen).contains { $0.id == "pool-house-adjacency" })
    }
}
