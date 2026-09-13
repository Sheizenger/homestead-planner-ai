import Testing
@testable import HomesteadEngine

/// The port's actual completion criterion, per AGENTS.md: the whole pipeline
/// — text parsing, sizing, placement, paths, fences, utility hookups, the
/// future-expansion reserve, analytics, and warnings, unplaced items and all
/// — reproducing every one of the 48 golden fixtures exactly. Every piece
/// has its own focused tests; this is the one that proves they compose
/// correctly together, in the same order `generate.ts` calls them.
@Test func generateMatchesEveryGoldenFixtureExactly() throws {
    let fixtures = try Fixtures.index()
    #expect(fixtures.count == 48)

    for entry in fixtures {
        let fixture = try Fixtures.golden(entry.file)
        let comment = Comment(rawValue: entry.file)

        // `.centers` is the frozen app's own (wrong) way of measuring a
        // separation, and these fixtures are its output — so the comparison
        // asks for it explicitly. The port's claim is "identical given the
        // same rules", not "identical forever"; `Constraints.SeparationPolicy`
        // says why the shipping default differs.
        let layout = Generate.variant(
            plot: fixture.input.plot,
            brief: fixture.input.brief,
            mode: fixture.input.mode,
            seed: fixture.input.seed,
            policy: .frozen
        )

        #expect(layout.strategyLabel == fixture.output.strategyLabel, comment)
        #expect(layout.mode == fixture.output.mode, comment)
        #expect(layout.seed == fixture.output.seed, comment)
        #expect(layout.zones == fixture.output.zones, comment)
        #expect(layout.objects == fixture.output.objects, comment)
        #expect(layout.paths == fixture.output.paths, comment)
        #expect(layout.fences == fixture.output.fences, comment)
        #expect(layout.utilityNodes == fixture.output.utilityNodes, comment)
        #expect(layout.analytics == fixture.output.analytics, comment)
        #expect(layout.warnings == fixture.output.warnings, comment)
    }
}

/// Water-loving types are the one part of the catalog the plot itself can
/// veto: `Placement` drops a dock or a turbine when no waterfront is
/// configured, because there is nowhere sensible to put one. That is correct,
/// and it is also invisible — a brief asking for a dock on a dry plot comes
/// back with no dock and nothing pointing at why. This pins both halves.
@Test func aDockOnlyAppearsWhenThePlotHasAWaterfront() {
    var inputs = StructuredInputs()
    inputs.infrastructure = ["dock"]
    let brief = Brief(structuredInputs: inputs)
    let boundary = PlotShape.rectangle(width: 60, height: 45)

    let dry = Generate.variant(plot: Plot(boundary: boundary), brief: brief, mode: .beautyBalanced, seed: 3)
    #expect(!dry.objects.contains { $0.typeId == "dock" })
    // It does warn — but with the generic "couldn't fit it anywhere, consider
    // a larger plot" text, which is the wrong advice here: the plot is nearly
    // empty and the real reason is that there is no water to build on. Ported
    // faithfully from the TypeScript, noted in BACKLOG.md, and softened in the
    // app by telling the user about the waterfront setting instead.
    #expect(dry.warnings.contains { $0.messageParams?["itemType"] == .string("dock") })

    let wet = Plot(
        boundary: boundary,
        waterfront: Waterfront(type: .river, edge: .north, widthM: 8, flowSpeedMps: 1.2, elevationDropM: 2)
    )
    let layout = Generate.variant(plot: wet, brief: brief, mode: .beautyBalanced, seed: 3)
    let dock = layout.objects.first { $0.typeId == "dock" }
    #expect(dock != nil)
    // And it lands in the water it needs, not on dry land somewhere.
    if let dock, let bounds = WaterfrontModel.bounds(of: wet) {
        #expect(dock.transform.y >= bounds.minY && dock.transform.y <= bounds.maxY)
    }
}
