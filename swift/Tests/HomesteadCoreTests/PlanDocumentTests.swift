import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

struct PlanDocumentTests {
    @Test func blankDocumentHasNoVariantsAndARectangularPlot() {
        let doc = PlanDocument.blank(name: "Test Plot", widthM: 30, heightM: 20)
        #expect(doc.variants.isEmpty)
        #expect(doc.activeVariantID == nil)
        #expect(doc.plot.boundary.count == 4)
        #expect(doc.schemaVersion == PlanDocument.currentSchemaVersion)
    }

    /// One JSON format for saving and export, per AGENTS.md — round-tripping
    /// it has to reproduce the document exactly, snapshot fields included,
    /// even though the running app never trusts those fields back.
    @Test func documentRoundTripsThroughJSON() throws {
        var doc = PlanDocument.blank(name: "Round Trip", widthM: 40, heightM: 30)
        doc.brief.structuredInputs.crops = ["potato", "orchard"]
        let layout = Generate.variant(plot: doc.plot, brief: doc.brief, mode: .beautyBalanced, seed: 42)
        let variant = Variant(generated: layout, plot: doc.plot, brief: doc.brief)
        doc.variants.append(variant)
        doc.activeVariantID = variant.id

        let data = try PlanDocumentCodec.encode(doc)
        let decoded = try PlanDocumentCodec.decode(data)

        #expect(decoded.name == doc.name)
        #expect(decoded.variants.count == 1)
        #expect(decoded.variants[0].objects == doc.variants[0].objects)
        #expect(decoded.variants[0].analyticsSnapshot == doc.variants[0].analyticsSnapshot)
        #expect(decoded.activeVariantID == doc.activeVariantID)
    }

    @Test func exportIsHumanReadable() throws {
        let doc = PlanDocument.blank(name: "Readable", widthM: 20, heightM: 20)
        let data = try PlanDocumentCodec.encode(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("\n"))
        #expect(text.contains("\"schemaVersion\""))
    }
}
