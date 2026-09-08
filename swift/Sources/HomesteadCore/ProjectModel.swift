import Foundation
import Observation
import HomesteadEngine

/// What `ProjectModel.applyQuickEdit` did with a parsed command. A semantic
/// result rather than a message string — the (future) panel maps this to
/// localized text, so Core never has to know what language is on screen.
public enum EditCommandOutcome: Equatable, Sendable {
    /// The text didn't parse as any known verb + object mention — including
    /// naming a type absent from the plan: `EditCommands.parse`'s
    /// candidates are built only from types actually present, so an absent
    /// type is never recognized as a mention in the first place, and there
    /// is no separate "named but not found" outcome to report.
    case notUnderstood
    /// The type exists, but only as the wrong lock state for this verb —
    /// e.g. "unlock the well" when every well present is already unlocked.
    case allMatchesLocked
    /// A move-near/away command found a reference object but nowhere on the
    /// plot fit the subject without overlapping something else.
    case noRoom
    case applied(verb: EditVerb, objectIds: [String])
}

/// The running state of one open project. Owns a `PlanDocument` and exposes
/// every mutation as a plain, undoable-by-the-caller method — see AGENTS.md
/// on why undo itself is not this class's job.
///
/// Analytics and warnings are deliberately absent as stored properties:
/// `analytics(for:)`/`warnings(for:)` recompute from the variant's current
/// `objects`/`zones` and the document's current `plot`/`brief` on every call.
/// A brief edit or an object drag can never leave them stale, because there
/// is nothing cached to go stale.
@Observable
public final class ProjectModel {
    public private(set) var document: PlanDocument

    public init(document: PlanDocument) {
        self.document = document
    }

    // MARK: - Reading

    public var activeVariant: Variant? {
        guard let id = document.activeVariantID else { return nil }
        return variant(id)
    }

    public func variant(_ id: Variant.ID) -> Variant? {
        document.variants.first { $0.id == id }
    }

    public func analytics(for variantID: Variant.ID) -> AnalyticsSnapshot? {
        guard let variant = variant(variantID) else { return nil }
        return Analytics.compute(objects: variant.objects, zones: variant.zones, plot: document.plot)
    }

    public func warnings(for variantID: Variant.ID) -> [Warning] {
        guard let variant = variant(variantID), let analytics = analytics(for: variantID) else { return [] }
        return Warnings.compute(
            objects: variant.objects,
            fences: variant.fences,
            analytics: analytics,
            plot: document.plot,
            householdSize: document.brief.structuredInputs.householdSize,
            climateZone: document.brief.structuredInputs.climateZone,
            crops: document.brief.structuredInputs.crops
        )
    }

    public func costEstimate(for variantID: Variant.ID, region: CostRegion) -> CostEstimate? {
        guard let variant = variant(variantID), let analytics = analytics(for: variantID) else { return nil }
        return Costs.estimate(objects: variant.objects, paths: variant.paths, fences: variant.fences, totalAreaM2: analytics.totalAreaM2, region: region)
    }

    public func materialsTakeoff(for variantID: Variant.ID) -> MaterialsTakeoff? {
        guard let variant = variant(variantID) else { return nil }
        return Materials.takeoff(objects: variant.objects, paths: variant.paths, fences: variant.fences)
    }

    /// True once the brief or the plot boundary has moved on since this
    /// variant was generated — the trigger for the "re-generate with the
    /// current brief" banner. A variant that no longer exists reads as not
    /// stale; there's nothing to prompt about.
    public func isStale(_ variantID: Variant.ID) -> Bool {
        guard let variant = variant(variantID) else { return false }
        return variant.generatedFromBrief != document.brief || variant.generatedFromPlotBoundary != document.plot.boundary
    }

    // MARK: - Brief and plot

    public func updateFreeText(_ text: String) {
        document.brief.freeText = text
        touch()
    }

    public func updateStructuredInputs(_ mutate: (inout StructuredInputs) -> Void) {
        mutate(&document.brief.structuredInputs)
        touch()
    }

    public func updatePlotBoundary(_ boundary: [Point]) {
        document.plot.boundary = boundary
        touch()
    }

    public func updateWaterfront(_ waterfront: Waterfront?) {
        document.plot.waterfront = waterfront
        touch()
    }

    public func updateElevation(_ elevation: PlotElevation?) {
        document.plot.elevation = elevation
        touch()
    }

    // MARK: - Variants

    /// Appends a freshly generated variant and leaves everything else
    /// untouched — the active variant stays active, and no existing variant
    /// is ever replaced or reset. "Generation adds" per AGENTS.md: work the
    /// user already did on another variant survives every call here,
    /// including a re-roll of the same mode.
    @discardableResult
    public func generateVariant(mode: PlanningMode, seed: Int) -> Variant.ID {
        let layout = Generate.variant(plot: document.plot, brief: document.brief, mode: mode, seed: seed)
        let variant = Variant(generated: layout, plot: document.plot, brief: document.brief)
        document.variants.append(variant)
        if document.activeVariantID == nil { document.activeVariantID = variant.id }
        touch()
        return variant.id
    }

    public func setActiveVariant(_ id: Variant.ID) {
        guard variant(id) != nil else { return }
        document.activeVariantID = id
    }

    public func renameVariant(_ id: Variant.ID, to label: String) {
        withVariant(id, markEdited: false) { $0.strategyLabel = label }
    }

    public func deleteVariant(_ id: Variant.ID) {
        document.variants.removeAll { $0.id == id }
        if document.activeVariantID == id {
            document.activeVariantID = document.variants.first?.id
        }
        touch()
    }

    // MARK: - Objects

    /// Refuses on a locked object, matching `Placement`'s own locked-object
    /// handling — silently, at this layer; the UI layer is responsible for
    /// surfacing that refusal instead of it vanishing the way the web app's
    /// delete-while-locked does (see BACKLOG.md).
    public func moveObject(_ objectID: String, in variantID: Variant.ID, to transform: Transform) {
        mutateObject(objectID, in: variantID) { $0.transform = transform }
    }

    public func resizeObject(_ objectID: String, in variantID: Variant.ID, to transform: Transform) {
        mutateObject(objectID, in: variantID) { $0.transform = transform }
    }

    public func toggleLock(_ objectID: String, in variantID: Variant.ID) {
        withVariant(variantID) { variant in
            guard let index = variant.objects.firstIndex(where: { $0.id == objectID }) else { return }
            variant.objects[index].locked.toggle()
        }
    }

    /// Deletes every unlocked object among `objectIDs`. Returns the ids that
    /// were actually removed, so a caller can tell the user when a locked
    /// selection blocked some of it rather than staying silent.
    @discardableResult
    public func deleteObjects(_ objectIDs: Set<String>, in variantID: Variant.ID) -> Set<String> {
        var removed: Set<String> = []
        withVariant(variantID) { variant in
            var kept: [PlanObject] = []
            kept.reserveCapacity(variant.objects.count)
            for object in variant.objects {
                if objectIDs.contains(object.id), !object.locked {
                    removed.insert(object.id)
                } else {
                    kept.append(object)
                }
            }
            variant.objects = kept
            variant.fences.removeAll { fence in removed.contains { fence.id == "fence-\($0)" } }
            variant.paths.removeAll { path in removed.contains { path.id == "path-\($0)" } }
            let remainingObjectIDs = Set(variant.objects.map(\.id))
            variant.utilityNodes = variant.utilityNodes.filter { remainingObjectIDs.contains($0.objectId) }
            let remainingNodeIDs = Set(variant.utilityNodes.map(\.id))
            for index in variant.utilityNodes.indices {
                variant.utilityNodes[index].connections = variant.utilityNodes[index].connections.filter(remainingNodeIDs.contains)
            }
        }
        return removed
    }

    /// Adds a fresh, unlocked instance of `typeId` at `transform` — the one
    /// authoring path the web app never had at all (see BACKLOG.md).
    @discardableResult
    public func addObject(typeId: String, transform: Transform, in variantID: Variant.ID) -> String? {
        guard let entry = ObjectLibrary[typeId] else { return nil }
        let id = "obj-\(typeId)-\(UUID().uuidString.prefix(8))"
        let object = PlanObject(
            id: id, typeId: typeId, category: entry.category, transform: transform,
            label: entry.label, locked: false, layerId: entry.category
        )
        withVariant(variantID) { $0.objects.append(object) }
        return id
    }

    @discardableResult
    public func duplicateObjects(_ objectIDs: Set<String>, in variantID: Variant.ID, offset: Point = Point(x: 2, y: 2)) -> [String] {
        var newIDs: [String] = []
        withVariant(variantID) { variant in
            for object in variant.objects where objectIDs.contains(object.id) {
                let newID = "obj-\(object.typeId)-\(UUID().uuidString.prefix(8))"
                var clone = object
                clone.id = newID
                clone.locked = false
                clone.transform.x += offset.x
                clone.transform.y += offset.y
                variant.objects.append(clone)
                newIDs.append(newID)
            }
        }
        return newIDs
    }

    // MARK: - Quick-edit text commands

    public func rotateObject90(_ objectID: String, in variantID: Variant.ID) {
        mutateObject(objectID, in: variantID) { $0.transform.rotationDeg = ($0.transform.rotationDeg + 90).truncatingRemainder(dividingBy: 360) }
    }

    /// Parses and applies a quick-edit command ("move the greenhouse near
    /// the well") in one step — `EditCommands.parse` plus the mutators
    /// above, so a caller (the eventual quick-edit panel) needs one method
    /// rather than re-deriving how a parsed command maps onto edits.
    ///
    /// The web app selects `subjects` by "matches `subjectTypeId` and isn't
    /// locked" *before* branching on the verb — which makes its `unlock`
    /// branch permanently dead: an object already excluded for being locked
    /// can never reach the `if (o.locked) toggleLock(o.id)` inside it, yet
    /// the web app reports success regardless (see BACKLOG.md). Locking
    /// wants unlocked targets, unlocking wants locked ones — the two are not
    /// the same filter, so this asks each verb which targets it actually
    /// wants rather than applying one blanket exclusion up front.
    @discardableResult
    public func applyQuickEdit(_ text: String, in variantID: Variant.ID) -> EditCommandOutcome {
        guard let variant = variant(variantID) else { return .notUnderstood }
        guard let parsed = EditCommands.parse(text, objectsPresent: variant.objects) else { return .notUnderstood }

        // `parsed.subjectTypeId` was matched against candidates built from
        // this same `variant.objects`, so a type match always exists; the
        // only way `subjects` can still come up empty is every match having
        // the wrong lock state for this verb.
        let wantsLocked = parsed.verb == .unlock
        let subjects = variant.objects.filter { $0.typeId == parsed.subjectTypeId && $0.locked == wantsLocked }
        guard !subjects.isEmpty else { return .allMatchesLocked }

        switch parsed.verb {
        case .delete:
            let removed = deleteObjects(Set(subjects.map(\.id)), in: variantID)
            return .applied(verb: parsed.verb, objectIds: Array(removed))
        case .duplicate:
            return .applied(verb: parsed.verb, objectIds: duplicateObjects(Set(subjects.map(\.id)), in: variantID))
        case .rotate:
            for subject in subjects { rotateObject90(subject.id, in: variantID) }
            return .applied(verb: parsed.verb, objectIds: subjects.map(\.id))
        case .lock, .unlock:
            for subject in subjects { toggleLock(subject.id, in: variantID) }
            return .applied(verb: parsed.verb, objectIds: subjects.map(\.id))
        case .enlarge, .shrink:
            var touched: [String] = []
            for subject in subjects {
                guard let entry = ObjectLibrary[subject.typeId] else { continue }
                let size = EditCommands.resizeTransform(entry: entry, current: subject.transform, grow: parsed.verb == .enlarge)
                resizeObject(subject.id, in: variantID, to: Transform(x: subject.transform.x, y: subject.transform.y, width: size.width, height: size.height, rotationDeg: subject.transform.rotationDeg))
                touched.append(subject.id)
            }
            return .applied(verb: parsed.verb, objectIds: touched)
        case .moveNear, .moveAway:
            // `EditCommands.parse` requires a non-nil `referenceTypeId` for
            // these two verbs, and — same reasoning as `subjectTypeId`
            // above — only ever sets it to a type present in this same
            // `variant.objects`, so both force-unwraps are guaranteed here.
            let reference = variant.objects.first { $0.typeId == parsed.referenceTypeId! }!
            let mode: EditCommands.RepositionMode = parsed.verb == .moveNear ? .near : .away
            var touched: [String] = []
            for subject in subjects {
                guard let target = EditCommands.findRepositionTarget(objects: variant.objects, plot: document.plot, subject: subject, reference: reference, mode: mode) else { continue }
                moveObject(subject.id, in: variantID, to: target)
                touched.append(subject.id)
            }
            return touched.isEmpty ? .noRoom : .applied(verb: parsed.verb, objectIds: touched)
        }
    }

    // MARK: - Private

    private func touch() {
        document.updatedAt = Date()
    }

    private func withVariant(_ id: Variant.ID, markEdited: Bool = true, _ mutate: (inout Variant) -> Void) {
        guard let index = document.variants.firstIndex(where: { $0.id == id }) else { return }
        mutate(&document.variants[index])
        if markEdited { document.variants[index].manuallyEdited = true }
        touch()
    }

    private func mutateObject(_ objectID: String, in variantID: Variant.ID, _ mutate: (inout PlanObject) -> Void) {
        withVariant(variantID) { variant in
            guard let index = variant.objects.firstIndex(where: { $0.id == objectID }), !variant.objects[index].locked else { return }
            mutate(&variant.objects[index])
        }
    }
}
