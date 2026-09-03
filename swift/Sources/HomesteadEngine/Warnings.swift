import Foundation

/// Rough planning guideline for a self-sufficient homestead (living space +
/// garden + some animals) — not a legal minimum, just a sanity check so a
/// large household isn't planned onto a plot that can't realistically fit
/// its program. Real sanitary-minimum norms (~15 m²/person) are for urban
/// housing and don't apply here.
public let RECOMMENDED_M2_PER_PERSON = 250

private let cropClimateNotes: [(crop: String, questionableZones: Set<ClimateZone>, severity: WarningSeverity, message: String)] = [
    ("vineyard", [.cold], .caution, "Grapevines usually need a longer, warmer growing season than a cold climate zone provides — consider cold-hardy cultivars or a greenhouse."),
    ("grain", [.arid], .info, "Grain in an arid zone will likely need irrigation to reach reasonable yields."),
    ("orchard", [.arid], .caution, "Most fruit trees need more consistent moisture than an arid climate provides without irrigation."),
    ("berries", [.arid, .subtropical], .caution, "Most berry brambles prefer cooler, moister conditions than this climate zone typically offers."),
    ("potato", [.subtropical, .arid], .info, "Potatoes generally yield better in cooler climates — expect lower yields or a need for irrigation here."),
]

/// Ported from `src/engine/warnings.ts`. Every warning-producing pass below
/// appends to a single array in the same order the original does — the final
/// sort is by severity only, and ties (routine, since most warnings are
/// `caution`) fall back to that insertion order. Swift's `sort` isn't stable,
/// so the sort carries an explicit index tie-break; get the insertion order
/// wrong anywhere upstream and this file's fixture comparisons fail even
/// though every individual warning it produces is individually correct.
public enum Warnings {
    public static func hydroFeasibilityWarnings(plot: Plot, objects: [PlanObject]) -> [Warning] {
        guard let turbine = objects.first(where: { $0.typeId == "micro-hydro" }), !WaterfrontModel.isHydroFeasible(plot) else { return [] }
        return [
            Warning(
                id: "warn-hydro-infeasible",
                severity: .caution,
                message: "The configured waterfront doesn't have enough flow speed or elevation drop for a micro-hydro turbine to generate meaningful power — consider a stronger site or reconsidering this feature.",
                messageKey: "warning.hydroInfeasible",
                ruleId: "hydro-infeasible",
                objectIds: [turbine.id]
            ),
        ]
    }

    public static func drainageWarnings(plot: Plot, objects: [PlanObject]) -> [Warning] {
        guard let elevation = plot.elevation, elevation.dropM > 0 else { return [] }
        guard let house = objects.first(where: { ObjectLibrary.houseTypeIDs.contains($0.typeId) }),
              let septic = objects.first(where: { $0.typeId == "septic" })
        else { return [] }
        let houseElevation = ElevationModel.elevation(on: plot, at: house.transform.center)
        let septicElevation = ElevationModel.elevation(on: plot, at: septic.transform.center)
        guard septicElevation > houseElevation + 0.05 else { return [] }
        let drop = NumberFormatting.toFixed(septicElevation - houseElevation, 1)
        return [
            Warning(
                id: "warn-septic-uphill",
                severity: .caution,
                message: "The septic system sits about \(drop) m uphill of the house on the configured slope — waste won't drain there by gravity and would need a lift pump.",
                messageKey: "warning.septicUphill",
                messageParams: ["drop": .string(drop)],
                ruleId: "septic-uphill",
                objectIds: [house.id, septic.id]
            ),
        ]
    }

    public static func householdAreaWarning(totalAreaM2: Double, householdSize: Int) -> Warning? {
        let recommended = householdSize * RECOMMENDED_M2_PER_PERSON
        guard totalAreaM2 < Double(recommended) else { return nil }
        let shortfall = Int((Double(recommended) - totalAreaM2).rounded(.up))
        let severity: WarningSeverity = totalAreaM2 < Double(recommended) * 0.6 ? .critical : .caution
        let recommendedText = NumberFormatting.usGrouped(recommended)
        let shortfallText = NumberFormatting.usGrouped(shortfall)
        return Warning(
            id: "warn-household-area-norm",
            severity: severity,
            message: "For \(householdSize) resident\(householdSize == 1 ? "" : "s"), a self-sufficient homestead typically needs around \(recommendedText) m² (~\(RECOMMENDED_M2_PER_PERSON) m²/person); this plot is short by about \(shortfallText) m². Consider a larger plot or a smaller household program.",
            messageKey: "warning.householdArea",
            messageParams: [
                "household": .number(Double(householdSize)),
                "recommended": .string(recommendedText),
                "perPerson": .number(Double(RECOMMENDED_M2_PER_PERSON)),
                "shortfall": .string(shortfallText),
            ],
            ruleId: "household-area-norm",
            objectIds: []
        )
    }

    public static func climateCropWarnings(climateZone: ClimateZone, crops: [String]) -> [Warning] {
        var warnings: [Warning] = []
        let cropSet = Set(crops)
        for note in cropClimateNotes {
            guard cropSet.contains(note.crop), note.questionableZones.contains(climateZone) else { continue }
            let capitalized = note.crop.prefix(1).uppercased() + note.crop.dropFirst()
            warnings.append(Warning(
                id: "warn-climate-\(note.crop)",
                severity: note.severity,
                message: "\(capitalized) in a \(climateZone.rawValue) climate: \(note.message)",
                messageKey: "warning.climateCropFit",
                messageParams: ["crop": .string(note.crop), "zone": .string(climateZone.rawValue)],
                ruleId: "climate-crop-fit",
                objectIds: []
            ))
        }
        return warnings
    }

    public static func compute(
        objects: [PlanObject],
        fences: [Fence],
        analytics: AnalyticsSnapshot,
        plot: Plot,
        householdSize: Int,
        climateZone: ClimateZone,
        crops: [String]
    ) -> [Warning] {
        var warnings: [Warning] = []

        if let household = householdAreaWarning(totalAreaM2: analytics.totalAreaM2, householdSize: householdSize) {
            warnings.append(household)
        }
        warnings.append(contentsOf: climateCropWarnings(climateZone: climateZone, crops: crops))
        warnings.append(contentsOf: hydroFeasibilityWarnings(plot: plot, objects: objects))
        warnings.append(contentsOf: drainageWarnings(plot: plot, objects: objects))

        // subjectTypes/relatedTypes can be the same list (e.g. "any two
        // outbuildings"), which would otherwise match a pair in both
        // directions and report it twice — dedupe on the unordered pair
        // regardless of which side matched "subject" vs "related".
        var reportedPairs = Set<String>()

        for constraint in Constraints.all {
            for subject in objects {
                guard let subjectEntry = ObjectLibrary[subject.typeId],
                      Constraints.matches(subjectEntry, constraint.subjectTypes)
                else { continue }
                for related in objects {
                    guard related.id != subject.id else { continue }
                    guard let relatedEntry = ObjectLibrary[related.typeId],
                          Constraints.matches(relatedEntry, constraint.relatedTypes)
                    else { continue }
                    // Roof-mounted equipment isn't a ground-level obstacle —
                    // skip ground clearance/separation checks (adjacency,
                    // e.g. cable-run distance, still applies).
                    if (constraint.kind == .separation || constraint.kind == .safety),
                       subject.metadata["roofMounted"]?.boolValue == true || related.metadata["roofMounted"]?.boolValue == true {
                        continue
                    }
                    let pairKey = "\(constraint.id):\([subject.id, related.id].sorted().joined(separator: "|"))"
                    guard !reportedPairs.contains(pairKey) else { continue }
                    let d = distance(subject.transform.center, related.transform.center)
                    if (constraint.kind == .separation || constraint.kind == .safety),
                       let minDistance = constraint.minDistance, d < minDistance {
                        reportedPairs.insert(pairKey)
                        warnings.append(Warning(
                            id: "warn-\(constraint.id)-\(subject.id)-\(related.id)",
                            severity: constraint.severity,
                            message: "\(subject.label) and \(related.label): \(constraint.message)",
                            messageKey: "warning.pair",
                            messageParams: ["ruleId": .string(constraint.id), "subjectType": .string(subject.typeId), "relatedType": .string(related.typeId)],
                            ruleId: constraint.id,
                            objectIds: [subject.id, related.id],
                            suggestedFix: SuggestedFix(label: "Move apart", action: "increase-separation")
                        ))
                    }
                    if constraint.kind == .adjacency, let maxDistance = constraint.maxDistance, d > maxDistance {
                        reportedPairs.insert(pairKey)
                        warnings.append(Warning(
                            id: "warn-\(constraint.id)-\(subject.id)-\(related.id)",
                            severity: constraint.severity,
                            message: "\(subject.label) and \(related.label): \(constraint.message)",
                            messageKey: "warning.pair",
                            messageParams: ["ruleId": .string(constraint.id), "subjectType": .string(subject.typeId), "relatedType": .string(related.typeId)],
                            ruleId: constraint.id,
                            objectIds: [subject.id, related.id],
                            suggestedFix: SuggestedFix(label: "Move closer", action: "decrease-separation")
                        ))
                    }
                }
            }
        }

        for object in objects {
            guard let entry = ObjectLibrary[object.typeId], entry.requiresFence else { continue }
            let hasFence = fences.contains { $0.id == "fence-\(object.id)" }
            if !hasFence {
                warnings.append(Warning(
                    id: "warn-unfenced-\(object.id)",
                    severity: .caution,
                    message: "\(object.label) normally requires containment fencing but none is present.",
                    messageKey: "warning.containmentRequired",
                    messageParams: ["subjectType": .string(object.typeId)],
                    ruleId: "containment-required",
                    objectIds: [object.id]
                ))
            }
        }

        for object in objects {
            guard let entry = ObjectLibrary[object.typeId] else { continue }
            for setback in Constraints.boundarySetbacks {
                guard Constraints.matches(entry, setback.appliesTo) else { continue }
                guard let d = Polygon.distanceToBoundary(object.transform.center, polygon: plot.boundary) else { continue }
                if d < setback.minDistanceM {
                    warnings.append(Warning(
                        id: "warn-\(setback.id)-\(object.id)",
                        severity: setback.severity,
                        message: "\(object.label) \(setback.message)",
                        messageKey: "warning.single",
                        messageParams: ["ruleId": .string(setback.id), "subjectType": .string(object.typeId)],
                        ruleId: setback.id,
                        objectIds: [object.id],
                        suggestedFix: SuggestedFix(label: "Move away from boundary", action: "increase-separation")
                    ))
                }
            }
        }

        for i in objects.indices {
            for j in (i + 1)..<objects.count {
                let a = objects[i]
                let b = objects[j]
                if a.metadata["roofMounted"]?.boolValue == true || b.metadata["roofMounted"]?.boolValue == true { continue }
                if a.transform.aabb.overlaps(b.transform.aabb) {
                    warnings.append(Warning(
                        id: "warn-overlap-\(a.id)-\(b.id)",
                        severity: .critical,
                        message: "\(a.label) and \(b.label) overlap on the plan.",
                        messageKey: "warning.overlap",
                        messageParams: ["subjectType": .string(a.typeId), "relatedType": .string(b.typeId)],
                        ruleId: "object-overlap",
                        objectIds: [a.id, b.id],
                        suggestedFix: SuggestedFix(label: "Move apart", action: "increase-separation")
                    ))
                }
            }
        }

        if analytics.allocatedAreaM2 > analytics.totalAreaM2 {
            let overPercent = Int(jsRound((analytics.allocatedAreaM2 - analytics.totalAreaM2) / analytics.totalAreaM2 * 100))
            warnings.append(Warning(
                id: "warn-overallocated",
                severity: .critical,
                message: "Plan exceeds the available plot area by \(overPercent)%. Reduce zone sizes or the plot's program.",
                messageKey: "warning.overallocated",
                messageParams: ["percent": .number(Double(overPercent))],
                ruleId: "capacity-overflow",
                objectIds: []
            ))
        } else if analytics.allocatedAreaM2 > analytics.totalAreaM2 * 0.9 {
            warnings.append(Warning(
                id: "warn-near-capacity",
                severity: .caution,
                message: "Plan uses over 90% of the plot, leaving little room for adjustment or future changes.",
                messageKey: "warning.nearCapacity",
                ruleId: "capacity-near-limit",
                objectIds: []
            ))
        }

        let severityRank: [WarningSeverity: Int] = [.critical: 0, .caution: 1, .info: 2]
        return warnings.enumerated()
            .sorted { lhs, rhs in
                let l = severityRank[lhs.element.severity]!
                let r = severityRank[rhs.element.severity]!
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
