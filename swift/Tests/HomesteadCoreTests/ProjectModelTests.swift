import Testing
import Foundation
import HomesteadEngine
@testable import HomesteadCore

struct ProjectModelTests {
    private func model(cropsForCompost: Bool = true) -> ProjectModel {
        var doc = PlanDocument.blank(name: "Family Plot", widthM: 50, heightM: 42)
        if cropsForCompost { doc.brief.structuredInputs.crops = ["potato", "vegetable"] }
        doc.brief.structuredInputs.householdSize = 3
        return ProjectModel(document: doc)
    }

    // MARK: - Generation accumulates

    /// The decision this whole layer exists to protect: generating never
    /// replaces or resets a variant the user already has open.
    @Test func generatingAppendsAndLeavesTheActiveVariantAlone() {
        let m = model()
        let first = m.generateVariant(mode: .beautyBalanced, seed: 42)
        m.setActiveVariant(first)
        m.moveObject(m.variant(first)!.objects[0].id, in: first, to: Transform(x: 5, y: 5, width: 1, height: 1))

        let second = m.generateVariant(mode: .productionMax, seed: 59)

        #expect(m.document.variants.count == 2)
        #expect(m.document.activeVariantID == first, "generating a second variant must not steal activation")
        #expect(m.variant(first)!.manuallyEdited)
        #expect(!m.variant(second)!.manuallyEdited)
    }

    @Test func firstGeneratedVariantBecomesActiveAutomatically() {
        let m = model()
        #expect(m.document.activeVariantID == nil)
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        #expect(m.document.activeVariantID == id)
    }

    @Test func deletingTheActiveVariantFallsBackToWhateverIsLeft() {
        let m = model()
        let a = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let b = m.generateVariant(mode: .productionMax, seed: 59)
        m.setActiveVariant(a)
        m.deleteVariant(a)
        #expect(m.document.activeVariantID == b)
        m.deleteVariant(b)
        #expect(m.document.activeVariantID == nil)
    }

    // MARK: - Derived analytics/warnings

    @Test func analyticsReflectABriefEditWithoutRegenerating() {
        let m = model(cropsForCompost: false)
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let before = m.analytics(for: id)!

        // 50x42 = 2100 m²; a household of 12 needs 3000 m² (250 m²/person),
        // which the plot falls short of.
        m.updateStructuredInputs { $0.householdSize = 12 }
        // Nothing about the plan itself changed — analytics are a pure
        // function of objects/zones/plot, not of the brief that produced
        // them, so they read identically...
        #expect(m.analytics(for: id) == before)
        // ...but a warning that depends on the *current* brief (household
        // area norm) picks the edit up immediately, because it is computed
        // fresh on every call rather than cached on the variant.
        #expect(m.warnings(for: id).contains { $0.ruleId == "household-area-norm" })
    }

    @Test func stalenessTracksBriefAndPlotChangesSeparately() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        #expect(!m.isStale(id))

        m.updateFreeText("more goats please")
        #expect(m.isStale(id))
    }

    @Test func stalenessTracksPlotBoundaryChanges() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        m.updatePlotBoundary(PlotShape.rectangle(width: 60, height: 50))
        #expect(m.isStale(id))
    }

    // MARK: - Object editing

    @Test func lockedObjectsRefuseMoveAndDelete() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let objectID = m.variant(id)!.objects[0].id
        m.toggleLock(objectID, in: id)

        let original = m.variant(id)!.objects[0].transform
        m.moveObject(objectID, in: id, to: Transform(x: 99, y: 99, width: 1, height: 1))
        #expect(m.variant(id)!.objects[0].transform == original)

        let removed = m.deleteObjects([objectID], in: id)
        #expect(removed.isEmpty)
        #expect(m.variant(id)!.objects.contains { $0.id == objectID })
    }

    @Test func deletingAnObjectReportsWhatWasActuallyRemoved() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let locked = m.variant(id)!.objects[0].id
        let unlocked = m.variant(id)!.objects[1].id
        m.toggleLock(locked, in: id)

        let removed = m.deleteObjects([locked, unlocked], in: id)
        #expect(removed == [unlocked])
        #expect(m.variant(id)!.objects.contains { $0.id == locked })
        #expect(!m.variant(id)!.objects.contains { $0.id == unlocked })
    }

    @Test func deletingAnObjectCleansUpItsFenceAndUtilityReferences() {
        var doc = PlanDocument.blank(name: "Water", widthM: 50, heightM: 42)
        doc.brief.structuredInputs.infrastructure = ["well"]
        let m = ProjectModel(document: doc)
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let well = m.variant(id)!.objects.first { $0.typeId == "well" }!
        #expect(m.variant(id)!.fences.contains { $0.id == "fence-\(well.id)" })
        #expect(m.variant(id)!.utilityNodes.contains { $0.objectId == well.id })

        _ = m.deleteObjects([well.id], in: id)
        #expect(!m.variant(id)!.fences.contains { $0.id == "fence-\(well.id)" })
        #expect(!m.variant(id)!.utilityNodes.contains { $0.objectId == well.id })
    }

    @Test func addObjectPlacesAKnownCatalogEntry() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let before = m.variant(id)!.objects.count

        let newID = m.addObject(typeId: "gazebo", transform: Transform(x: 10, y: 10, width: 4, height: 4), in: id)
        #expect(newID != nil)
        #expect(m.variant(id)!.objects.count == before + 1)
        #expect(m.variant(id)!.objects.last?.typeId == "gazebo")
        #expect(m.variant(id)!.manuallyEdited)

        #expect(m.addObject(typeId: "not-a-real-type", transform: Transform(x: 0, y: 0, width: 1, height: 1), in: id) == nil)
    }

    @Test func duplicateObjectsOffsetsAndUnlocksTheCopy() {
        let m = model()
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        let original = m.variant(id)!.objects[0]
        m.toggleLock(original.id, in: id)

        let newIDs = m.duplicateObjects([original.id], in: id)
        #expect(newIDs.count == 1)
        let clone = m.variant(id)!.objects.first { $0.id == newIDs[0] }!
        #expect(!clone.locked)
        #expect(clone.transform.x == original.transform.x + 2)
        #expect(clone.transform.y == original.transform.y + 2)
    }
}
