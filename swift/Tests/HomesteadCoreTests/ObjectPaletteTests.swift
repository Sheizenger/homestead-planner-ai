import Testing
import HomesteadEngine
@testable import HomesteadCore

struct ObjectPaletteTests {
    @Test func emptyQueryReturnsTheWholeCatalog() {
        #expect(ObjectPalette.search("").count == ObjectLibrary.all.count)
        #expect(ObjectPalette.search("   ").count == ObjectLibrary.all.count)
    }

    @Test func matchesTheLabelSubstringCaseInsensitively() {
        let results = ObjectPalette.search("shed")
        #expect(results.contains { $0.id == "shed" })
        #expect(results.contains { $0.id == "woodshed" }) // "Woodshed" contains "shed"
        let upper = ObjectPalette.search("SHED")
        #expect(upper.map(\.id) == results.map(\.id))
    }

    @Test func matchesTheIdWhenTheLabelDiffers() {
        // "solar-array"'s label is "Solar Panels" — the id itself should
        // still be searchable.
        #expect(ObjectPalette.search("solar-array").contains { $0.id == "solar-array" })
    }

    @Test func noMatchesReturnsAnEmptyList() {
        #expect(ObjectPalette.search("xyzzy-not-a-real-thing").isEmpty)
    }
}
