import Testing
import HomesteadEngine
@testable import HomesteadCore

struct QuickEditTests {
    private func model() -> (ProjectModel, Variant.ID) {
        var doc = PlanDocument.blank(name: "Family Plot", widthM: 50, heightM: 42)
        doc.brief.structuredInputs.householdSize = 3
        doc.brief.structuredInputs.infrastructure = ["well"]
        let m = ProjectModel(document: doc)
        let id = m.generateVariant(mode: .beautyBalanced, seed: 42)
        return (m, id)
    }

    @Test func unrecognizedTextIsReportedAsNotUnderstood() {
        let (m, id) = model()
        #expect(m.applyQuickEdit("do something inscrutable", in: id) == .notUnderstood)
    }

    /// `EditCommands.parse`'s candidates are built only from types present
    /// in the plan (see `moveNearWithAnAbsentReferenceTypeNeverParses`
    /// below for the same reasoning on the reference side), so naming an
    /// absent type is never recognized as a mention at all — this reads as
    /// `.notUnderstood`, not a distinct "object not found" outcome.
    @Test func namingAnAbsentTypeNeverParses() {
        let (m, id) = model()
        #expect(m.applyQuickEdit("delete the vineyard", in: id) == .notUnderstood)
    }

    @Test func deleteRemovesEveryUnlockedMatchAndReportsItsIds() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!
        let outcome = m.applyQuickEdit("delete the tool shed", in: id)
        #expect(outcome == .applied(verb: .delete, objectIds: [shed.id]))
        #expect(!m.variant(id)!.objects.contains { $0.id == shed.id })
    }

    /// The type exists but the only instance of it is locked: distinct from
    /// "doesn't exist at all" — a locked shed is a real object the user can
    /// see, just not one this verb may touch.
    @Test func deleteReportsAllMatchesLockedRatherThanNotFound() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!
        m.toggleLock(shed.id, in: id)
        #expect(m.applyQuickEdit("delete the tool shed", in: id) == .allMatchesLocked)
        #expect(m.variant(id)!.objects.contains { $0.id == shed.id })
    }

    @Test func rotateAdds90DegreesAndWrapsAt360() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!
        let before = shed.transform.rotationDeg
        _ = m.applyQuickEdit("rotate the tool shed", in: id)
        let after = m.variant(id)!.objects.first { $0.id == shed.id }!.transform.rotationDeg
        #expect(after == (before + 90).truncatingRemainder(dividingBy: 360))
    }

    @Test func enlargeAndShrinkScaleWithinCatalogBounds() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!
        let before = shed.transform

        _ = m.applyQuickEdit("make the tool shed bigger", in: id)
        let grown = m.variant(id)!.objects.first { $0.id == shed.id }!.transform
        #expect(grown.width > before.width)

        _ = m.applyQuickEdit("shrink the tool shed", in: id)
        let shrunk = m.variant(id)!.objects.first { $0.id == shed.id }!.transform
        #expect(shrunk.width < grown.width)
    }

    /// The fix this file exists to prove: unlocking a locked object actually
    /// unlocks it, unlike the web app's dead `unlock` branch (see
    /// BACKLOG.md) — "already unlocked" and "locked, now freed" are
    /// different requests, not the same filter.
    @Test func lockAndUnlockTargetOppositeLockStates() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!

        // "unlock" when nothing of that type is locked: no eligible target.
        #expect(m.applyQuickEdit("unlock the tool shed", in: id) == .allMatchesLocked)

        let lockOutcome = m.applyQuickEdit("lock the tool shed", in: id)
        #expect(lockOutcome == .applied(verb: .lock, objectIds: [shed.id]))
        #expect(m.variant(id)!.objects.first { $0.id == shed.id }!.locked)

        // Now that it's locked, "lock" again finds nothing eligible...
        #expect(m.applyQuickEdit("lock the tool shed", in: id) == .allMatchesLocked)
        // ...but "unlock" does, and actually flips it back.
        let unlockOutcome = m.applyQuickEdit("unlock the tool shed", in: id)
        #expect(unlockOutcome == .applied(verb: .unlock, objectIds: [shed.id]))
        #expect(!m.variant(id)!.objects.first { $0.id == shed.id }!.locked)
    }

    /// `EditCommands.parse`'s candidates are built only from types present
    /// in the plan, so a reference naming an absent type is never even
    /// recognized as a mention — the command reads as one mention short of
    /// what "near"/"away" require, and fails to parse at all rather than
    /// parsing and then failing to resolve the reference. (The web app's
    /// QuickEditPanel has an "if reference not found" branch after parsing
    /// that is dead code for the identical reason — a parsed
    /// `referenceTypeId` can only ever name a type that was already present
    /// to be found as a mention.)
    @Test func moveNearWithAnAbsentReferenceTypeNeverParses() {
        let (m, id) = model()
        #expect(m.applyQuickEdit("move the tool shed near the vineyard", in: id) == .notUnderstood)
    }

    @Test func moveNearRelocatesTheSubjectTowardTheReference() {
        let (m, id) = model()
        let shed = m.variant(id)!.objects.first { $0.typeId == "shed" }!
        let well = m.variant(id)!.objects.first { $0.typeId == "well" }!
        let distanceBefore = distance(shed.transform.center, well.transform.center)

        let outcome = m.applyQuickEdit("move the tool shed near the well", in: id)
        guard case .applied(let verb, let ids) = outcome else {
            Issue.record("expected .applied, got \(outcome)")
            return
        }
        #expect(verb == .moveNear)
        #expect(ids == [shed.id])
        let after = m.variant(id)!.objects.first { $0.id == shed.id }!
        #expect(distance(after.transform.center, well.transform.center) < distanceBefore)
    }
}
