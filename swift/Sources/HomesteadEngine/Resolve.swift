import Foundation

/// One-click fixes for the warnings the planner raises — `PRD.md` FR-18,
/// which the web app has the data model for (`Warning.suggestedFix`) and no
/// implementation of: the label is rendered nowhere and the action string is
/// read by nothing.
///
/// The objective here is deliberately *not* the one `EditCommands`
/// `.away` reposition uses. "As far from the paddock as the plot allows"
/// answers the letter of the warning by throwing the pool into the opposite
/// corner and wrecking everything else about the plan. A fix should be the
/// smallest move that clears the rule and leaves the object no worse off
/// against every other rule it is subject to — the nudge a person would make
/// by hand.
public enum Resolve {
    public struct Fix: Equatable, Sendable {
        public let objectId: String
        public let transform: Transform
        /// How far the object travels, in metres — the UI says so, because a
        /// fix that silently moves something 30 m away is not a fix.
        public let distanceM: Double
    }

    /// The smallest move that clears `warning`, or `nil` when there isn't one
    /// — an unplaced-item warning has no positional answer, a locked object
    /// won't move, and a plot can simply be too full. Callers must treat
    /// `nil` as "tell the user", not as "nothing happened".
    public static func fix(
        for warning: Warning,
        objects: [PlanObject],
        plot: Plot,
        region: RegulatoryRegion = .generic,
        policy: Constraints.SeparationPolicy = .corrected
    ) -> Fix? {
        guard rule(warning.ruleId, region: region, policy: policy) != nil else { return nil }
        guard let bounds = plot.bounds else { return nil }

        let involved = warning.objectIds.compactMap { id in objects.first { $0.id == id } }
        let movable = involved.filter { !$0.locked }
        guard !movable.isEmpty else { return nil }

        // Whichever of the pair is the less anchored thing: the house is what
        // a homestead is arranged around, and a 300 m² orchard is not what
        // anybody means by "move it a bit".
        let ordered = movable.sorted { a, b in
            let aAnchor = isAnchor(a)
            let bAnchor = isAnchor(b)
            if aAnchor != bAnchor { return !aAnchor }
            let aArea = a.transform.width * a.transform.height
            let bArea = b.transform.width * b.transform.height
            if aArea != bArea { return aArea < bArea }
            return a.id < b.id
        }

        for subject in ordered {
            guard let entry = ObjectLibrary[subject.typeId] else { continue }
            let others = objects.filter { $0.id != subject.id }
            let before = shortfall(
                subject.transform, entry: entry, among: others, plot: plot, region: region, policy: policy
            )
            let step = max(0.5, min(bounds.width, bounds.height) / 60)
            let rings = max(1, Int(reach(bounds) / step))

            for ring in 1...rings {
                let radius = step * Double(ring)
                for heading in headings {
                    let candidate = Transform(
                        x: subject.transform.x + cos(heading) * radius,
                        y: subject.transform.y + sin(heading) * radius,
                        width: subject.transform.width,
                        height: subject.transform.height,
                        rotationDeg: subject.transform.rotationDeg
                    )
                    guard Polygon.contains(candidate, polygon: plot.boundary) else { continue }
                    let aabb = candidate.aabb
                    guard !others.contains(where: { aabb.overlaps($0.transform.aabb, margin: 0.3) }) else { continue }
                    guard satisfies(warning.ruleId, transform: candidate, entry: entry,
                                    among: others, plot: plot, region: region, policy: policy) else { continue }
                    // Clearing one rule by breaking another is not a fix.
                    let after = shortfall(
                        candidate, entry: entry, among: others, plot: plot, region: region, policy: policy
                    )
                    guard after <= before else { continue }
                    return Fix(objectId: subject.id, transform: candidate, distanceM: radius)
                }
            }
        }
        return nil
    }

    // MARK: - Rules

    /// Rings are searched outward, so the first hit is the smallest move, and
    /// the search stops where "nudge" stops being true. A third of the plot's
    /// short side, capped at 20 m: past that the object is being evicted to
    /// somewhere else entirely, which is a re-generation, not a fix, and the
    /// caller is better told there is no small answer. Costs 11% of the
    /// warnings a fix (89% of them offered → 84%), and brings the mean move
    /// down from 5.6 m to 2.6 m.
    private static func reach(_ bounds: Rect) -> Double {
        min(min(bounds.width, bounds.height) / 3, 20)
    }
    private static let headings: [Double] = (0..<24).map { Double($0) * .pi / 12 }

    private enum Rule {
        case pair(Constraint)
        case setback(BoundarySetback)
    }

    private static func rule(_ id: String, region: RegulatoryRegion, policy: Constraints.SeparationPolicy) -> Rule? {
        if let constraint = Constraints.all(for: region, policy: policy).first(where: { $0.id == id }) {
            return .pair(constraint)
        }
        if let setback = Constraints.boundarySetbacks(for: region).first(where: { $0.id == id }) {
            return .setback(setback)
        }
        return nil
    }

    /// The house anchors the plan; anything very large is scenery you lay a
    /// plan around rather than something you shuffle.
    private static func isAnchor(_ object: PlanObject) -> Bool {
        if ObjectLibrary.houseTypeIDs.contains(object.typeId) { return true }
        return object.transform.width * object.transform.height > 200
    }

    private static func satisfies(
        _ ruleId: String,
        transform: Transform,
        entry: ObjectLibrary.Entry,
        among others: [PlanObject],
        plot: Plot,
        region: RegulatoryRegion,
        policy: Constraints.SeparationPolicy
    ) -> Bool {
        switch rule(ruleId, region: region, policy: policy) {
        case let .pair(constraint):
            return pairShortfall(constraint, transform, entry: entry, among: others, policy: policy) == 0
        case let .setback(setback):
            return setbackShortfall(setback, transform, entry: entry, plot: plot, policy: policy) == 0
        case nil:
            return false
        }
    }

    /// Total metres by which `transform` falls short of every separation,
    /// safety and setback rule that applies to it. Adjacency is deliberately
    /// left out: it is a maximum, and pulling an object back towards its pump
    /// is a different fix from pushing it away from the goats.
    private static func shortfall(
        _ transform: Transform,
        entry: ObjectLibrary.Entry,
        among others: [PlanObject],
        plot: Plot,
        region: RegulatoryRegion,
        policy: Constraints.SeparationPolicy
    ) -> Double {
        var total = 0.0
        for constraint in Constraints.all(for: region, policy: policy) {
            total += pairShortfall(constraint, transform, entry: entry, among: others, policy: policy)
        }
        for setback in Constraints.boundarySetbacks(for: region) {
            total += setbackShortfall(setback, transform, entry: entry, plot: plot, policy: policy)
        }
        return total
    }

    private static func pairShortfall(
        _ constraint: Constraint,
        _ transform: Transform,
        entry: ObjectLibrary.Entry,
        among others: [PlanObject],
        policy: Constraints.SeparationPolicy
    ) -> Double {
        guard constraint.kind == .separation || constraint.kind == .safety,
              let minDistance = constraint.minDistance else { return 0 }
        // Both directions, for the same reason `Placement` checks both: a
        // rule written subject→related still binds when this object is the
        // related half of the pair.
        let asSubject = Constraints.matches(entry, constraint.subjectTypes)
        let asRelated = Constraints.matches(entry, constraint.relatedTypes)
        guard asSubject || asRelated else { return 0 }

        var total = 0.0
        for other in others {
            guard let otherEntry = ObjectLibrary[other.typeId] else { continue }
            let matches = asSubject
                ? Constraints.matches(otherEntry, constraint.relatedTypes)
                : Constraints.matches(otherEntry, constraint.subjectTypes)
            guard matches else { continue }
            // Roof-mounted kit isn't a ground-level neighbour — the same
            // exclusion `Warnings` makes, or a fix would chase a phantom.
            guard other.metadata["roofMounted"]?.boolValue != true else { continue }
            let gap = Constraints.separation(transform, other.transform, policy)
            if gap < minDistance { total += minDistance - gap }
        }
        return total
    }

    private static func setbackShortfall(
        _ setback: BoundarySetback,
        _ transform: Transform,
        entry: ObjectLibrary.Entry,
        plot: Plot,
        policy: Constraints.SeparationPolicy
    ) -> Double {
        guard Constraints.matches(entry, setback.appliesTo),
              let clearance = Constraints.boundaryClearance(transform, boundary: plot.boundary, policy)
        else { return 0 }
        return clearance < setback.minDistanceM ? setback.minDistanceM - clearance : 0
    }
}
