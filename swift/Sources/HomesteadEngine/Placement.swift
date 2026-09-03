import Foundation

/// The autoplanning search, ported from `src/engine/placement.ts`.
///
/// This is the highest-risk file in the whole port. A single shared RNG
/// stream feeds both the candidate-position jitter and the object-id suffix,
/// and every candidate the search grid visits draws from it — including ones
/// rejected a moment later — so the loop structure has to visit the same grid
/// points, in the same order, drawing at the same points, as the original.
/// One skipped or extra iteration desyncs every draw after it, and with it
/// every object placed afterward. `PlacementTests` checks this the only way
/// that actually proves it: byte-for-byte equality against `placement.json`,
/// generated straight from `placeObjects` itself, ids included — a matching
/// id is what proves the draw sequence stayed aligned this far.
public enum Placement {
    public struct Result: Equatable, Sendable {
        public var objects: [PlanObject]
        public var unplaced: [Sizing.ProgramItem]
    }

    private struct ModeWeights {
        var access: Double
        var separation: Double
        var sun: Double
        var beauty: Double
    }

    private struct LayoutParams {
        var spacingPad: Double
        var comfortDist: Double
        var compactPullScale: Double
    }

    private struct Candidate {
        var transform: Transform
        var score: Double
        var reasons: [String]
    }

    /// Fraction of the house footprint realistically usable for roof-mount PV
    /// (one south-facing slope, minus dormers/chimneys/valleys) — a coarse
    /// stand-in for a real roof-plane model.
    private static let roofUsableFraction = 0.5

    /// Belong on/right at the water and are the only types allowed inside the
    /// waterfront strip — everything else is excluded from it.
    private static let waterLovingTypes: Set<String> = ["dock", "micro-hydro"]

    /// Categories that read as "private/technical" and shouldn't crowd the
    /// direct house-to-gate approach — the one strip of yard every visitor
    /// actually sees and walks through.
    private static let frontAvoidCategories: Set<ObjectCategory> = [.utility, .water, .energy, .storage, .animal, .leisure]
    private static let sideYardCategories: Set<ObjectCategory> = [.utility, .water, .energy]

    /// Coarse placement tiers: structures/utilities go first as spatial
    /// anchors, then animals, then food zones, then incidental extras. Within
    /// a tier, items place largest-first so big fields claim open space
    /// before small beds nibble at what's left — plain priority-order
    /// placement otherwise starves large production-scaled fields that
    /// happen to sort late.
    private static let placementTiers: [[String]] = [
        ["house", "house-l"],
        ["garage", "shed", "barn", "cellar", "woodshed", "workshop"],
        ["well", "pump", "septic", "water-tank", "rainwater-cistern", "solar-array", "battery-room", "inverter-room", "generator", "micro-hydro", "dock"],
        // Greenhouses/hydroponics need both sun AND close utility hookups —
        // their own tier right after utilities, rather than lumped in with
        // the big annual fields below, so they get first pick of a spot
        // satisfying both instead of large fields claiming all the good
        // ground first.
        ["greenhouse", "hydroponic-tower"],
        ["goat-shelter", "goat-paddock", "poultry-coop", "apiary"],
        ["raised-beds", "vegetable-area", "potato-area", "grain-field", "orchard-trees", "berry-rows", "vineyard"],
        ["compost", "patio", "pool", "gazebo", "banya", "smokehouse"],
    ]

    private static func tier(of typeId: String) -> Int {
        placementTiers.firstIndex { $0.contains(typeId) } ?? placementTiers.count
    }

    private static let modeWeights: [PlanningMode: ModeWeights] = [
        .productionMax: ModeWeights(access: 1, separation: 1, sun: 2.2, beauty: 0.2),
        .minimumMaintenance: ModeWeights(access: 2.2, separation: 0.8, sun: 1, beauty: 0.3),
        .beautyBalanced: ModeWeights(access: 1.2, separation: 1.1, sun: 1.2, beauty: 1.8),
        .safetyFirst: ModeWeights(access: 1, separation: 2.2, sun: 1, beauty: 0.3),
    ]

    public static func placeObjects(
        plot: Plot,
        program: [Sizing.ProgramItem],
        mode: PlanningMode,
        seed: Int
    ) -> Result {
        let rand = RandomStream(seed: seed)
        let bounds = plot.bounds ?? Rect(minX: 0, minY: 0, width: 0, height: 0)
        let plotW = bounds.width
        let plotH = bounds.height
        let step = max(1.2, min(plotW, plotH) / 28)
        let weights = modeWeights[mode]!

        // How much slack the plot has relative to the requested program: 0
        // means the program nearly fills the plot (pack tight), higher means
        // real room to spare. The same program on a much bigger plot should
        // read as more spread out, not identically cramped.
        let plotArea = Polygon.area(plot.boundary)
        let programArea = program.reduce(0.0) { $0 + $1.size.width * $1.size.height * Double($1.count) }
        let slackRatio = plotArea > 0 ? min(1, max(0, (plotArea - programArea) / plotArea)) : 0
        let layout = LayoutParams(
            spacingPad: 1.2 + slackRatio * 5,
            comfortDist: 10 + slackRatio * 8,
            compactPullScale: 0.15 * (1 - slackRatio * 0.75)
        )

        // A stable sort with an explicit tie-break: JavaScript's `sort` is
        // stable and Swift's is not, and the comparator ties whenever two
        // items share a tier and an area — routine among same-type crops.
        let sorted = program.enumerated().sorted { lhs, rhs in
            let tierDiff = tier(of: lhs.element.typeId) - tier(of: rhs.element.typeId)
            if tierDiff != 0 { return tierDiff < 0 }
            let areaDiff = (rhs.element.size.width * rhs.element.size.height) - (lhs.element.size.width * lhs.element.size.height)
            if areaDiff != 0 { return areaDiff < 0 }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var placed: [PlanObject] = plot.existingObjects.map { existing in
            let category = ObjectLibrary[existing.type]?.category ?? .residential
            return PlanObject(
                id: existing.id,
                typeId: existing.type,
                category: category,
                transform: existing.transform,
                label: existing.label,
                locked: true,
                layerId: category,
                metadata: [:]
            )
        }
        var unplaced: [Sizing.ProgramItem] = []

        var houseCenter: Transform? = placed.first { ObjectLibrary.houseTypeIDs.contains($0.typeId) }?.transform
        let waterfrontBounds = WaterfrontModel.bounds(of: plot)

        for item in sorted {
            guard let entry = ObjectLibrary[item.typeId] else { continue }
            let width = item.size.width
            let height = item.size.height

            if waterLovingTypes.contains(item.typeId), waterfrontBounds == nil {
                // A dock or micro-hydro turbine was requested but no
                // waterfront is configured — nowhere sensible to put it.
                unplaced.append(item)
                continue
            }

            if item.typeId == "solar-array", let house = houseCenter {
                let roofArea = house.width * house.height * roofUsableFraction
                if width * height <= roofArea {
                    let roofW = min(width, house.width * 0.8)
                    let roofH = min(height, house.height * 0.8)
                    var metadata = item.metadata
                    metadata["roofMounted"] = .bool(true)
                    metadata["rationaleTokens"] = .array([.string("roofMounted")])
                    placed.append(PlanObject(
                        id: "obj-\(item.typeId)-\(placed.count)-\(Int(floor(rand.next() * 1e6)))",
                        typeId: item.typeId,
                        category: entry.category,
                        transform: Transform(
                            x: house.x + (house.width - roofW) * 0.2,
                            y: house.y - (house.height - roofH) * 0.2,
                            width: roofW,
                            height: roofH,
                            rotationDeg: house.rotationDeg
                        ),
                        label: entry.label,
                        locked: false,
                        layerId: entry.category,
                        metadata: metadata
                    ))
                    continue
                }
            }

            let isWaterLoving = waterLovingTypes.contains(item.typeId)
            // Dock/micro-hydro search only the waterfront strip itself (they
            // belong on the water); everything else is hard-excluded from
            // that strip so a barn or vegetable bed never lands in the river.
            let searchBounds = isWaterLoving ? waterfrontBounds! : bounds
            let avoidBounds = isWaterLoving ? nil : waterfrontBounds

            var best = searchBestCandidate(
                plot: plot, bounds: searchBounds, step: step, width: width, height: height,
                entry: entry, placed: placed, houseCenter: houseCenter, weights: weights,
                rand: rand, layout: layout, avoidBounds: avoidBounds
            )
            for shrink in [0.8, 0.6, 0.45] {
                if best != nil { break }
                best = searchBestCandidate(
                    plot: plot, bounds: searchBounds, step: step, width: width * shrink, height: height * shrink,
                    entry: entry, placed: placed, houseCenter: houseCenter, weights: weights,
                    rand: rand, layout: layout, avoidBounds: avoidBounds
                )
            }
            guard let chosen = best else {
                unplaced.append(item)
                continue
            }

            var metadata = item.metadata
            metadata["rationaleTokens"] = .array(orderedUnique(chosen.reasons).map(JSONValue.string))
            let object = PlanObject(
                id: "obj-\(item.typeId)-\(placed.count)-\(Int(floor(rand.next() * 1e6)))",
                typeId: item.typeId,
                category: entry.category,
                transform: chosen.transform,
                label: entry.label,
                locked: false,
                layerId: entry.category,
                metadata: metadata
            )
            placed.append(object)
            if ObjectLibrary.houseTypeIDs.contains(item.typeId) { houseCenter = object.transform }
        }

        return Result(objects: placed, unplaced: unplaced)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted { result.append(value) }
        return result
    }

    private static func searchBestCandidate(
        plot: Plot,
        bounds: Rect,
        step: Double,
        width: Double,
        height: Double,
        entry: ObjectLibrary.Entry,
        placed: [PlanObject],
        houseCenter: Transform?,
        weights: ModeWeights,
        rand: RandomStream,
        layout: LayoutParams,
        avoidBounds: Rect?
    ) -> Candidate? {
        let orientations = width == height ? [0] : [0, 90]
        var best: Candidate?

        var x = bounds.minX + width / 2
        while x <= bounds.maxX - width / 2 {
            var y = bounds.minY + height / 2
            while y <= bounds.maxY - height / 2 {
                for rot in orientations {
                    let w = rot == 90 ? height : width
                    let h = rot == 90 ? width : height
                    let transform = Transform(
                        x: x + (rand.next() - 0.5) * step * 0.3,
                        y: y + (rand.next() - 0.5) * step * 0.3,
                        width: w,
                        height: h,
                        rotationDeg: 0
                    )
                    guard Polygon.contains(transform, polygon: plot.boundary) else { continue }

                    let aabb = transform.aabb
                    if let avoidBounds, aabb.overlaps(avoidBounds) { continue }

                    let overlaps = placed.contains { aabb.overlaps($0.transform.aabb, margin: layout.spacingPad) }
                    if overlaps { continue }

                    let hardViolation = Constraints.all.contains { constraint in
                        guard constraint.hard,
                              constraint.kind == .separation || constraint.kind == .safety,
                              let minDistance = constraint.minDistance
                        else { return false }
                        // Checked both ways: a pair like well/septic must not
                        // end up close together regardless of which of the
                        // two happens to get placed first — matching
                        // subjectTypes-only would silently stop enforcing
                        // this the moment the "related" side is placed
                        // before the "subject" side ever exists to check.
                        let asSubject = Constraints.matches(entry, constraint.subjectTypes)
                        let asRelated = Constraints.matches(entry, constraint.relatedTypes)
                        guard asSubject || asRelated else { return false }
                        return placed.contains { other in
                            guard let otherEntry = ObjectLibrary[other.typeId] else { return false }
                            let otherMatches = asSubject
                                ? Constraints.matches(otherEntry, constraint.relatedTypes)
                                : Constraints.matches(otherEntry, constraint.subjectTypes)
                            guard otherMatches else { return false }
                            return distance(transform.center, other.transform.center) < minDistance
                        }
                    }
                    if hardViolation { continue }

                    let candidate = scoreCandidate(
                        transform: transform, entry: entry, placed: placed, houseCenter: houseCenter,
                        bounds: bounds, weights: weights, boundary: plot.boundary, layout: layout, plot: plot
                    )
                    if best == nil || candidate.score > best!.score {
                        best = Candidate(transform: transform, score: candidate.score, reasons: candidate.reasons)
                    }
                }
                y += step
            }
            x += step
        }
        return best
    }

    private static func scoreCandidate(
        transform: Transform,
        entry: ObjectLibrary.Entry,
        placed: [PlanObject],
        houseCenter: Transform?,
        bounds: Rect,
        weights: ModeWeights,
        boundary: [Point],
        layout: LayoutParams,
        plot: Plot
    ) -> (score: Double, reasons: [String]) {
        var score = 0.0
        var reasons: [String] = []

        if let house = houseCenter, !ObjectLibrary.houseTypeIDs.contains(entry.id) {
            let d = distance(transform.center, house.center)
            if entry.needsAccess {
                // Diminishing returns on closeness: within "comfortable
                // walking distance" shaving off another metre barely
                // matters, so the search doesn't fight to snap every
                // frequently-visited object flush against the house wall —
                // beyond it, distance costs more steeply. This is what lets
                // a bigger plot with the same objects read as more spread
                // out instead of identically huddled around the house.
                let penalty = d <= layout.comfortDist
                    ? d * 0.3
                    : layout.comfortDist * 0.3 + (d - layout.comfortDist) * 1.4
                score -= penalty * weights.access
                if d < layout.comfortDist { reasons.append("accessClose") }
            } else {
                // Mild preference for compactness even for low-visit zones.
                score -= d * weights.access * layout.compactPullScale
            }

            // Sector siting: the house has a road-facing front (the direct
            // approach from the gate, kept clear for entry) and a private
            // back yard opposite it, per the same south/road-facing
            // convention used for house placement and the gate.
            let relX = transform.x - house.x
            let relY = transform.y - house.y // + toward the gate/road, - away from it (back yard)

            // Layout convention, not an aesthetic-mode preference — kept
            // independent of weights.beauty so septic-behind-the-house or
            // patio-by-the-potatoes doesn't come back the moment someone
            // picks Production-Maximizing.
            let sectorWeight = 0.7 + weights.separation * 0.15

            if entry.category == .leisure {
                // Outdoor living space belongs in the private back yard, not
                // staged between the house and the road.
                if relY < 0 {
                    score += min(-relY, 10) * sectorWeight
                    reasons.append("backYard")
                } else {
                    score -= relY * sectorWeight * 0.8
                }
            } else if frontAvoidCategories.contains(entry.category) {
                // Keep the direct house-to-gate approach clear of clutter.
                let frontHalfWidth = house.width / 2 + 2
                if relY > 1, abs(relX) < frontHalfWidth {
                    score -= 15 * sectorWeight
                }
            }

            if sideYardCategories.contains(entry.category) {
                // Technical/utility items conventionally sit in a side yard,
                // not dead-centre behind the house.
                score += min(abs(relX), 12) * sectorWeight * 0.3
                if abs(relX) < house.width * 0.25 {
                    score -= 6 * sectorWeight
                }
            }
        } else if houseCenter == nil {
            // House placement: bias toward the "front" (larger y =
            // south/road side by convention).
            score += (transform.y - bounds.minY) * 1.5
            reasons.append("roadFacing")
        }

        for setback in Constraints.boundarySetbacks {
            guard Constraints.matches(entry, setback.appliesTo) else { continue }
            guard let d = Polygon.distanceToBoundary(transform.center, polygon: boundary) else { continue }
            if d < setback.minDistanceM {
                score -= (setback.minDistanceM - d) * weights.separation * 2
            } else {
                reasons.append("boundaryClear")
            }
        }

        for constraint in Constraints.all {
            // Checked both ways — see the matching comment in
            // searchBestCandidate's hard-violation check: a directional
            // subjectTypes/relatedTypes match would only ever influence
            // placement of whichever side of the pair is placed second.
            let asSubject = Constraints.matches(entry, constraint.subjectTypes)
            let asRelated = Constraints.matches(entry, constraint.relatedTypes)
            guard asSubject || asRelated else { continue }
            for other in placed {
                guard let otherEntry = ObjectLibrary[other.typeId] else { continue }
                let otherMatches = asSubject
                    ? Constraints.matches(otherEntry, constraint.relatedTypes)
                    : Constraints.matches(otherEntry, constraint.subjectTypes)
                guard otherMatches else { continue }
                let d = distance(transform.center, other.transform.center)
                if (constraint.kind == .separation || constraint.kind == .safety),
                   let minDistance = constraint.minDistance, d < minDistance {
                    score -= (minDistance - d) * weights.separation
                    reasons.append("apartFrom:\(other.typeId)")
                }
                if constraint.kind == .adjacency, let maxDistance = constraint.maxDistance {
                    // Adjacency is a functional requirement, not an
                    // aesthetic taste — keep it meaningfully strong even in
                    // modes that otherwise weight "access" low, so a plan
                    // doesn't rack up avoidable adjacency warnings just
                    // because the active mode deprioritizes walking
                    // distance. Every mode should still try to satisfy
                    // these; they should just differ in everything else.
                    let adjacencyPull = max(weights.access, 1.3)
                    if d > maxDistance {
                        score -= (d - maxDistance) * adjacencyPull * 1.8
                    } else {
                        score += (maxDistance - d) * adjacencyPull * 0.6
                        reasons.append("near:\(other.typeId)")
                    }
                }
            }
        }

        if entry.id == "septic", let house = houseCenter, plot.elevation != nil {
            // Gravity drainage: a septic system should sit downhill of the
            // house so waste flows there on its own rather than needing a
            // lift pump.
            let septicElevation = ElevationModel.elevation(on: plot, at: transform.center)
            let houseElevation = ElevationModel.elevation(on: plot, at: house.center)
            if septicElevation < houseElevation - 0.05 {
                score += (houseElevation - septicElevation) * 4
                reasons.append("downhill")
            } else if septicElevation > houseElevation + 0.05 {
                score -= (septicElevation - houseElevation) * 6
            }
        }

        if entry.sunNeed == .full {
            let southness = transform.y - bounds.minY
            score += southness * weights.sun * 0.6
            let shadeCastingCategories: Set<ObjectCategory> = [.residential, .foodPerennial, .storage]
            let shaded = placed.contains { other in
                guard let otherEntry = ObjectLibrary[other.typeId], shadeCastingCategories.contains(otherEntry.category) else { return false }
                let isNorthOfCandidate = other.transform.y < transform.y
                let withinShadowBand = abs(other.transform.x - transform.x) < (other.transform.width + transform.width)
                let closeEnough = transform.y - other.transform.y < other.transform.height * 2.5
                return isNorthOfCandidate && withinShadowBand && closeEnough
            }
            if shaded {
                score -= 40 * weights.sun
            } else {
                reasons.append("sunClear")
            }
        }

        if entry.noiseLevel == .loud || entry.odorLevel == .strong {
            let distToBoundary = min(
                min(transform.x - bounds.minX, bounds.maxX - transform.x),
                min(transform.y - bounds.minY, bounds.maxY - transform.y)
            )
            score += distToBoundary * weights.separation * 0.3
        }

        if weights.beauty > 1 {
            let alignsWithExisting = placed.contains {
                abs($0.transform.x - transform.x) < 1.5 || abs($0.transform.y - transform.y) < 1.5
            }
            if alignsWithExisting {
                score += 12 * weights.beauty
                reasons.append("aligned")
            }
        }

        return (score, reasons)
    }
}

/// Wraps `Mulberry32`'s value semantics in a reference so a single stream can
/// be threaded through the placement search's many function calls exactly as
/// the shared closure in `placement.ts` is — every call site advances the
/// same stream, in the same order, rather than a copy of it.
public final class RandomStream {
    private var generator: Mulberry32
    public init(seed: Int) { generator = Mulberry32(seed: seed) }
    public func next() -> Double { generator.next() }
}
