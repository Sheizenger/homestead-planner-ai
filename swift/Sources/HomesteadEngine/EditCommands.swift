import Foundation

/// Bounded-vocabulary quick-edit commands, ported from
/// `src/engine/editCommands.ts` — the same spirit as `TextParser`'s brief
/// extraction: free text is matched against a fixed set of verbs and the
/// object labels actually present in the current plan, rather than sent to
/// an open-ended model, so results stay deterministic and explainable.
/// "Present in the plan" is correct here, not a bug to fix: every verb below
/// edits an object that has to already exist to be moved, resized, deleted,
/// or locked. (Adding a new object is a different action entirely —
/// `ObjectPalette`'s job, not this file's.)
public enum EditVerb: String, Codable, Sendable {
    case moveNear = "move-near"
    case moveAway = "move-away"
    case enlarge
    case shrink
    case delete
    case duplicate
    case rotate
    case lock
    case unlock
}

public struct ParsedEditCommand: Equatable, Sendable {
    public let verb: EditVerb
    public let subjectTypeId: String
    public let referenceTypeId: String?
}

public enum EditCommands {
    /// Order matters: more specific phrases ("away from") are tested before
    /// broader ones that would otherwise win first, and delete/duplicate/
    /// rotate/lock take priority over resize or move phrasing that might
    /// incidentally share a word.
    private static let verbPatterns: [(verb: EditVerb, pattern: String)] = [
        (.delete, #"\b(delete|remove)\b"#),
        (.duplicate, #"\b(duplicate|copy|clone)\b"#),
        (.rotate, #"\b(rotate|turn)\b"#),
        (.unlock, #"\bunlock\b"#),
        (.lock, #"\block\b"#),
        (.enlarge, #"\b(bigger|larger|enlarge|increase|grow|expand)\b"#),
        (.shrink, #"\b(smaller|shrink|decrease|reduce|shrink)\b"#),
        (.moveAway, #"\b(away from|farther from|further from|far from)\b"#),
        (.moveNear, #"\b(near|closer to|next to|beside|by the)\b"#),
    ]

    private static func findVerb(_ text: String) -> EditVerb? {
        for (verb, pattern) in verbPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return verb }
        }
        return nil
    }

    /// Longest-label-first so a multi-word label ("Solar Panels") wins over
    /// any shorter label another entry might share a substring with; each
    /// matched span is consumed so the same text isn't double-counted.
    private static func findObjectMentions(_ text: String, candidates: [(typeId: String, label: String)]) -> [(typeId: String, index: Int)] {
        let sorted = candidates.sorted { $0.label.count > $1.label.count }
        var found: [(typeId: String, index: Int)] = []
        var consumed: [(Int, Int)] = []
        for candidate in sorted {
            guard let range = text.range(of: candidate.label) else { continue }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = start + candidate.label.count
            let overlaps = consumed.contains { start < $0.1 && end > $0.0 }
            if overlaps { continue }
            found.append((candidate.typeId, start))
            consumed.append((start, end))
        }
        return found.sorted { $0.index < $1.index }
    }

    public static func parse(_ text: String, objectsPresent: [PlanObject]) -> ParsedEditCommand? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty, let verb = findVerb(lower) else { return nil }

        var seenTypeIds = Set<String>()
        var presentTypeIds: [String] = []
        for object in objectsPresent where seenTypeIds.insert(object.typeId).inserted {
            presentTypeIds.append(object.typeId)
        }
        let candidates = presentTypeIds
            .map { (typeId: $0, label: (ObjectLibrary[$0]?.label ?? $0).lowercased()) }
            .filter { !$0.label.isEmpty }

        let mentions = findObjectMentions(lower, candidates: candidates)
        guard let first = mentions.first else { return nil }

        let referenceTypeId = mentions.count > 1 ? mentions[1].typeId : nil
        if (verb == .moveNear || verb == .moveAway), referenceTypeId == nil { return nil }

        return ParsedEditCommand(verb: verb, subjectTypeId: first.typeId, referenceTypeId: referenceTypeId)
    }

    public static func resizeTransform(entry: ObjectLibrary.Entry, current: Transform, grow: Bool) -> Size {
        let factor = grow ? 1.2 : 0.8
        return Size(
            width: clamp(current.width * factor, entry.minimumSize.width, entry.defaultSize.width * 2.5),
            height: clamp(current.height * factor, entry.minimumSize.height, entry.defaultSize.height * 2.5)
        )
    }

    public enum RepositionMode {
        case near, away
    }

    /// Scans the plot for the best non-overlapping spot for `subject`
    /// (keeping its own size/rotation) that is as close to (`.near`) or as
    /// far from (`.away`) `reference` as the plot allows — the same coarse
    /// grid-scan `Placement` uses, but single-purpose: no sun/adjacency/
    /// setback scoring, since a quick-edit move should behave like dragging
    /// the object by hand, not like re-running generation.
    public static func findRepositionTarget(objects: [PlanObject], plot: Plot, subject: PlanObject, reference: PlanObject, mode: RepositionMode) -> Transform? {
        guard let bounds = plot.bounds else { return nil }
        let w = subject.transform.width
        let h = subject.transform.height
        let step = max(0.5, min(bounds.width, bounds.height) / 40)
        let others = objects.filter { $0.id != subject.id }

        var best: (transform: Transform, score: Double)?
        var x = bounds.minX + w / 2
        while x <= bounds.maxX - w / 2 {
            var y = bounds.minY + h / 2
            while y <= bounds.maxY - h / 2 {
                let transform = Transform(x: x, y: y, width: w, height: h, rotationDeg: subject.transform.rotationDeg)
                if Polygon.contains(transform, polygon: plot.boundary) {
                    let aabb = transform.aabb
                    let overlapsAny = others.contains { aabb.overlaps($0.transform.aabb, margin: 0.3) }
                    if !overlapsAny {
                        let d = distance(transform.center, reference.transform.center)
                        let score = mode == .near ? -d : d
                        if best == nil || score > best!.score { best = (transform, score) }
                    }
                }
                y += step
            }
            x += step
        }
        return best?.transform
    }
}
