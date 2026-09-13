import Testing
@testable import HomesteadEngine

/// Holds the planner to the separations it claims to enforce.
///
/// The frozen web app measures every separation centre to centre, which makes
/// the requirement scale with the size of the objects instead of staying the
/// distance it says it is. The effect is not subtle: on an ordinary plan it
/// leaves a pool a few metres from a goat paddock while a 12 m
/// animal-to-leisure separation reports itself satisfied, and does the same to
/// the fire separations. These tests are the measurement, not an opinion.
struct SeparationQualityTests {
    /// A brief with enough in it to compete for space — three animals-and-
    /// leisure pairs, a fire-separation pair, and crops to crowd them.
    private static func brief(householdSize: Int = 4) -> Brief {
        var inputs = StructuredInputs()
        inputs.householdSize = householdSize
        inputs.animals = [AnimalRequest(type: "goats", count: 6), AnimalRequest(type: "poultry", count: 20)]
        inputs.infrastructure = ["pool", "well", "septic", "greenhouse", "workshop", "sauna", "compost"]
        inputs.crops = ["vegetables", "orchard", "berries"]
        return Brief(structuredInputs: inputs)
    }

    /// Total metres by which the plan falls short of its own separation rules,
    /// measured between footprints — the honest reading, whatever the planner
    /// used to place them.
    private static func shortfall(_ layout: Layout) -> (total: Double, count: Int) {
        var total = 0.0
        var count = 0
        for constraint in Constraints.all where constraint.kind == .separation || constraint.kind == .safety {
            guard let minDistance = constraint.minDistance else { continue }
            for a in layout.objects {
                guard let aEntry = ObjectLibrary[a.typeId],
                      Constraints.matches(aEntry, constraint.subjectTypes),
                      a.metadata["roofMounted"]?.boolValue != true
                else { continue }
                for b in layout.objects where b.id > a.id {
                    guard let bEntry = ObjectLibrary[b.typeId],
                          Constraints.matches(bEntry, constraint.relatedTypes),
                          b.metadata["roofMounted"]?.boolValue != true
                    else { continue }
                    let gap = Polygon.clearance(a.transform.corners, b.transform.corners)
                    if gap < minDistance {
                        total += minDistance - gap
                        count += 1
                    }
                }
            }
        }
        return (total, count)
    }

    private static func sweep(_ policy: Constraints.SeparationPolicy) -> (shortfall: Double, violations: Int, unplaced: Int) {
        var total = 0.0
        var violations = 0
        var unplaced = 0
        for (width, height) in [(60.0, 45.0), (80.0, 60.0)] {
            for mode in PlanningMode.allCases {
                for seed in 1...3 {
                    let plot = Plot(boundary: PlotShape.rectangle(width: width, height: height))
                    let layout = Generate.variant(plot: plot, brief: brief(), mode: mode, seed: seed, policy: policy)
                    let result = shortfall(layout)
                    total += result.total
                    violations += result.count
                    unplaced += layout.warnings.filter { $0.ruleId == "capacity-overflow" }.count
                }
            }
        }
        return (total, violations, unplaced)
    }

    /// The headline claim, as a comparison rather than an absolute: measuring
    /// between footprints and penalising a near-total failure harder than a
    /// near-miss cuts the plans' real separation debt by more than half. Stated
    /// as a ratio so the test survives ordinary tuning and only fails if the
    /// improvement is actually given up.
    @Test func measuringBetweenFootprintsHalvesTheSeparationDebt() {
        let legacy = Self.sweep(.frozen)
        let corrected = Self.sweep(.corrected)

        #expect(corrected.shortfall < legacy.shortfall * 0.5)
        #expect(corrected.violations < legacy.violations)
        // Keeping things apart must not be bought by leaving them out.
        #expect(corrected.unplaced <= legacy.unplaced)
    }

    /// The specific complaint this came from: a swimming pool sited against a
    /// goat paddock. Both are large, so centre-to-centre reads a comfortable
    /// gap where the tape would read a few metres.
    @Test func aPoolIsNotPutUpAgainstTheGoatPen() {
        var worstLegacy = Double.infinity
        var worstCorrected = Double.infinity

        for seed in 1...6 {
            let plot = Plot(boundary: PlotShape.rectangle(width: 80, height: 60))
            for policy in [Constraints.SeparationPolicy.frozen, .corrected] {
                let layout = Generate.variant(plot: plot, brief: Self.brief(), mode: .beautyBalanced, seed: seed, policy: policy)
                guard let pool = layout.objects.first(where: { $0.typeId == "pool" }) else { continue }
                for animal in layout.objects where ObjectLibrary[animal.typeId]?.category == .animal {
                    let gap = Polygon.clearance(pool.transform.corners, animal.transform.corners)
                    if policy == .frozen {
                        worstLegacy = min(worstLegacy, gap)
                    } else {
                        worstCorrected = min(worstCorrected, gap)
                    }
                }
            }
        }

        #expect(worstLegacy.isFinite)
        #expect(worstCorrected.isFinite)
        #expect(worstCorrected > worstLegacy)
        // Not the full 12 m — on a plot this size with this program that isn't
        // always geometrically available, and the plan says so in a warning
        // rather than pretending. But never against the fence either.
        #expect(worstCorrected >= 5)
    }

    /// And when it can't be helped, it is reported. Under the frozen reading
    /// the same plan stays silent, which is the part that makes it a trap
    /// rather than a trade-off.
    @Test func aSeparationItCannotHonourIsAtLeastReported() {
        let plot = Plot(boundary: PlotShape.rectangle(width: 55, height: 40))
        let layout = Generate.variant(plot: plot, brief: Self.brief(householdSize: 6), mode: .productionMax, seed: 2)

        let debt = Self.shortfall(layout)
        let reported = Set(layout.warnings.map(\.ruleId))
        if debt.count > 0 {
            #expect(!reported.isDisjoint(with: Set(Constraints.all.map(\.id))))
        }
    }
}
