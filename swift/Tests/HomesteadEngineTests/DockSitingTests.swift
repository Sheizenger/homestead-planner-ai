import Testing
@testable import HomesteadEngine

/// A pier runs out from the bank, not along it.
///
/// The generic search treated a dock like any other box: it tried both
/// orientations, scored them on access and sun the way it scores a shed, and
/// parked a 2.5 x 6 pier broadside in the middle of the river with a path
/// walking up to its long edge. Where a dock goes is not a search problem.
struct DockSitingTests {
    private func brief() -> Brief {
        var inputs = StructuredInputs()
        inputs.householdSize = 4
        inputs.infrastructure = ["dock"]
        return Brief(structuredInputs: inputs)
    }

    private func plot(_ edge: PlotEdge) -> Plot {
        Plot(
            boundary: PlotShape.rectangle(width: 80, height: 60),
            waterfront: Waterfront(type: .lake, edge: edge, widthM: 12, flowSpeedMps: nil, elevationDropM: nil)
        )
    }

    @Test func thePierRunsOutFromWhicheverBankTheWaterIsOn() throws {
        for edge in PlotEdge.allCases {
            let plot = self.plot(edge)
            let water = try #require(WaterfrontModel.bounds(of: plot))
            let layout = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: 4)
            let dock = try #require(layout.objects.first { $0.typeId == "dock" }, Comment(rawValue: "\(edge)"))
            let comment = Comment(rawValue: "\(edge): \(dock.transform)")

            let alongShore = edge == .north || edge == .south
            // Long axis across the water, short axis along the shore.
            if alongShore {
                #expect(dock.transform.height > dock.transform.width, comment)
            } else {
                #expect(dock.transform.width > dock.transform.height, comment)
            }

            // And it reaches the bank rather than floating mid-channel.
            let aabb = dock.transform.aabb
            let touchesBank: Bool
            switch edge {
            case .north: touchesBank = abs(aabb.maxY - water.maxY) < 1.0
            case .south: touchesBank = abs(aabb.minY - water.minY) < 1.0
            case .west: touchesBank = abs(aabb.maxX - water.maxX) < 1.0
            case .east: touchesBank = abs(aabb.minX - water.minX) < 1.0
            }
            #expect(touchesBank, comment)

            // Still in the water it is a dock for.
            #expect(WaterfrontModel.bounds(of: plot).map { aabb.minY >= $0.minY - 0.01 && aabb.maxY <= $0.maxY + 0.01 || aabb.minX >= $0.minX - 0.01 && aabb.maxX <= $0.maxX + 0.01 } == true, comment)
        }
    }

    /// The frozen reading still searches for a spot, which is what the golden
    /// fixtures record.
    @Test func theFrozenRulebookStillSearches() throws {
        let plot = self.plot(.north)
        let corrected = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: 4)
            .objects.first { $0.typeId == "dock" }
        let frozen = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: 4, policy: .frozen)
            .objects.first { $0.typeId == "dock" }
        #expect(corrected != nil)
        #expect(frozen != nil)
        #expect(corrected?.transform != frozen?.transform)
    }
}
