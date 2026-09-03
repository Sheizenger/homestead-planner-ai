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

        let layout = Generate.variant(plot: fixture.input.plot, brief: fixture.input.brief, mode: fixture.input.mode, seed: fixture.input.seed)

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
