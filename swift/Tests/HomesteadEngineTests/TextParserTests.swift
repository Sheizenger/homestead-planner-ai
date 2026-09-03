import Testing
@testable import HomesteadEngine

/// Expected values below are captured by running the actual TypeScript
/// `parseFreeText`/`mergeFreeTextIntoStructured` in Node, not inferred from
/// reading the source — the ordering rules in particular are easy to get
/// subtly wrong by reasoning alone.
struct TextParserTests {
    @Test func infrastructureTermsMatchInDeclarationOrder() {
        let result = TextParser.parse("we also want a big apiary and a smokehouse")
        #expect(result.infrastructure == ["apiary", "smokehouse"])
        #expect(result.crops.isEmpty)
        #expect(result.animals.isEmpty)
    }

    @Test func synonymsCollapseToOneValueAtFirstOccurrence() {
        // "chicken", "hens" and "poultry" all resolve to "poultry"; only one
        // entry should appear, and multi-word terms tokenize into the same
        // consumed words a single-word synonym would.
        let result = TextParser.parse("chickens and hens and poultry, plus a raised bed")
        #expect(result.animals == ["poultry"])
        #expect(result.crops == ["raised-beds"])
    }

    @Test func styleWordsSumAndModesDeduplicate() {
        let result = TextParser.parse("something beautiful and ornamental, but balanced and beautiful too")
        #expect(result.aestheticDelta == 45) // beautiful(20) + ornamental(25)
        #expect(result.suggestedModes == [.beautyBalanced])
    }

    @Test func householdSizeMatchesEitherCapturingGroup() {
        #expect(TextParser.parse("a family of 5 wants a garden").householdSize == 5)
        #expect(TextParser.parse("we are 3 adults on this plot").householdSize == 3)
        #expect(TextParser.parse("no number here").householdSize == nil)
    }

    @Test func unrecognizedTermsExcludeConsumedWordsAndStopwordsAndShortWords() {
        let result = TextParser.parse("xyzzy quux something completely unrecognized words here appear")
        // "something" is a stopword; every remaining word is length > 3 and
        // unconsumed, so all survive, in first-appearance order, capped at 12.
        #expect(result.unrecognizedTerms == [
            "xyzzy", "quux", "completely", "unrecognized", "words", "here", "appear",
        ])
    }

    @Test func multiWordTermTokensAreConsumedIndividually() {
        // "raised bed" consumes both "raised" and "bed" as words, even though
        // "bed" alone is never a dictionary term.
        let result = TextParser.parse("a raised bed for my family")
        #expect(!result.unrecognizedTerms.contains("raised"))
        #expect(result.crops == ["raised-beds"])
    }

    /// `[^a-z\s]` in the original deletes non-letters outright rather than
    /// blanking them to a space, so punctuation between two letters fuses
    /// them into one token instead of leaving a gap.
    @Test func punctuationFusesAdjacentLettersRatherThanSeparatingThem() {
        let result = TextParser.parse("don't want raised-beds or a low-maintenance yard")
        #expect(result.unrecognizedTerms == ["dont", "raisedbeds", "lowmaintenance", "yard"])
        #expect(result.suggestedModes == [.minimumMaintenance])
    }

    @Test func emptyTextExtractsNothing() {
        let result = TextParser.parse("")
        #expect(result == TextParser.Extraction(
            crops: [], animals: [], infrastructure: [],
            aestheticDelta: 0, suggestedModes: [], householdSize: nil, unrecognizedTerms: []
        ))
    }

    @Test func mergeAddsWithoutOverridingStructuredFields() {
        var base = StructuredInputs()
        base.crops = ["potato"]
        base.animals = []
        base.infrastructure = ["well"]
        base.aestheticPreference = 50
        base.householdSize = 4

        let extraction = TextParser.Extraction(
            crops: ["orchard"], animals: ["poultry"], infrastructure: ["compost"],
            aestheticDelta: 20, suggestedModes: [], householdSize: 9, unrecognizedTerms: []
        )
        let merged = TextParser.merge(base, with: extraction)

        // householdSize: structured wins when non-zero.
        #expect(merged.householdSize == 4)
        #expect(merged.crops == ["potato", "orchard"])
        // animals: only filled from free text when structured had none.
        #expect(merged.animals == [AnimalRequest(type: "poultry", count: 6)])
        #expect(merged.infrastructure == ["well", "compost"])
        #expect(merged.aestheticPreference == 70)
    }

    @Test func mergeFallsBackToExtractedHouseholdSizeThenToOne() {
        var withoutHousehold = StructuredInputs()
        withoutHousehold.householdSize = 0

        let withExtraction = TextParser.merge(
            withoutHousehold,
            with: TextParser.Extraction(
                crops: [], animals: [], infrastructure: [], aestheticDelta: 0,
                suggestedModes: [], householdSize: 7, unrecognizedTerms: []
            )
        )
        #expect(withExtraction.householdSize == 7)

        let withNeither = TextParser.merge(
            withoutHousehold,
            with: TextParser.Extraction(
                crops: [], animals: [], infrastructure: [], aestheticDelta: 0,
                suggestedModes: [], householdSize: nil, unrecognizedTerms: []
            )
        )
        #expect(withNeither.householdSize == 1)
    }

    @Test func aestheticPreferenceClampsToPercentRange() {
        var base = StructuredInputs()
        base.aestheticPreference = 90
        let pushedOver = TextParser.merge(
            base,
            with: TextParser.Extraction(
                crops: [], animals: [], infrastructure: [], aestheticDelta: 30,
                suggestedModes: [], householdSize: nil, unrecognizedTerms: []
            )
        )
        #expect(pushedOver.aestheticPreference == 100)

        base.aestheticPreference = 5
        let pushedUnder = TextParser.merge(
            base,
            with: TextParser.Extraction(
                crops: [], animals: [], infrastructure: [], aestheticDelta: -25,
                suggestedModes: [], householdSize: nil, unrecognizedTerms: []
            )
        )
        #expect(pushedUnder.aestheticPreference == 0)
    }
}
