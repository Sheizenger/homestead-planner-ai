import Testing
@testable import HomesteadEngine

/// `PRD.md` FR-18, which until now existed only as a label on a struct.
struct ResolveTests {
    private static func brief() -> Brief {
        var inputs = StructuredInputs()
        inputs.householdSize = 4
        inputs.animals = [AnimalRequest(type: "goats", count: 6), AnimalRequest(type: "poultry", count: 20)]
        inputs.infrastructure = ["pool", "well", "septic", "greenhouse", "workshop", "sauna", "compost"]
        inputs.crops = ["vegetables", "orchard", "berries"]
        return Brief(structuredInputs: inputs)
    }

    /// A plan with at least one positional warning, so the tests below are
    /// exercising a real one rather than a constructed toy.
    private static func plannedCase() -> (plot: Plot, layout: Layout, warning: Warning)? {
        let plot = Plot(boundary: PlotShape.rectangle(width: 80, height: 60))
        for seed in 1...12 {
            let layout = Generate.variant(plot: plot, brief: brief(), mode: .beautyBalanced, seed: seed)
            let fixable = layout.warnings.first { warning in
                warning.objectIds.count >= 1
                    && (Constraints.all.contains { $0.id == warning.ruleId }
                        || Constraints.boundarySetbacks.contains { $0.id == warning.ruleId })
            }
            if let fixable { return (plot, layout, fixable) }
        }
        return nil
    }

    @Test func aFixClearsTheWarningItWasAskedAbout() throws {
        let scenario = try #require(Self.plannedCase())
        let fix = try #require(Resolve.fix(for: scenario.warning, objects: scenario.layout.objects, plot: scenario.plot))

        var moved = scenario.layout.objects
        let index = try #require(moved.firstIndex { $0.id == fix.objectId })
        moved[index].transform = fix.transform

        // Recomputing the whole warning pass is the honest check: the fix has
        // to survive the same code that raised the complaint, not a private
        // re-derivation of it.
        let after = Warnings.compute(
            objects: moved,
            fences: scenario.layout.fences,
            analytics: Analytics.compute(objects: moved, zones: scenario.layout.zones, plot: scenario.plot),
            plot: scenario.plot,
            householdSize: 4,
            climateZone: .temperate,
            crops: Self.brief().structuredInputs.crops
        )
        #expect(!after.contains { $0.id == scenario.warning.id })
    }

    /// The point of the whole design: the smallest move, not the furthest.
    /// `EditCommands.findRepositionTarget(.away)` maximises distance, which
    /// answers the letter of the warning by throwing the object into the far
    /// corner — this must not do that.
    @Test func aFixIsANudgeNotAnEviction() throws {
        let scenario = try #require(Self.plannedCase())
        let fix = try #require(Resolve.fix(for: scenario.warning, objects: scenario.layout.objects, plot: scenario.plot))
        let bounds = try #require(scenario.plot.bounds)

        #expect(fix.distanceM > 0)
        #expect(fix.distanceM < min(bounds.width, bounds.height) / 2)
    }

    @Test func theFixedObjectStaysInsideThePlotAndOffItsNeighbours() throws {
        let scenario = try #require(Self.plannedCase())
        let fix = try #require(Resolve.fix(for: scenario.warning, objects: scenario.layout.objects, plot: scenario.plot))

        #expect(Polygon.contains(fix.transform, polygon: scenario.plot.boundary))
        for other in scenario.layout.objects where other.id != fix.objectId {
            #expect(!fix.transform.aabb.overlaps(other.transform.aabb))
        }
    }

    /// A warning with no positional answer must say so rather than move
    /// something at random and look like it worked.
    @Test func warningsWithNoPositionalAnswerAreDeclined() {
        let plot = Plot(boundary: PlotShape.rectangle(width: 60, height: 45))
        let unplaced = Warning(
            id: "warn-unplaced-dock",
            severity: .critical,
            message: "Could not fit dock",
            ruleId: "capacity-overflow",
            objectIds: []
        )
        #expect(Resolve.fix(for: unplaced, objects: [], plot: plot) == nil)
    }

    /// Locking means "don't move this", including on the planner's own
    /// initiative.
    @Test func aLockedObjectIsNeverMoved() throws {
        let scenario = try #require(Self.plannedCase())
        var locked = scenario.layout.objects
        for index in locked.indices where scenario.warning.objectIds.contains(locked[index].id) {
            locked[index].locked = true
        }
        #expect(Resolve.fix(for: scenario.warning, objects: locked, plot: scenario.plot) == nil)
    }
}
