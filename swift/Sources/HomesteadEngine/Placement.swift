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

    /// How much harder a near-total separation failure is penalised than a
    /// near-miss. Chosen from a 144-plan sweep (`SeparationQualityTests` runs
    /// a smaller version of it); the total shortfall across the sweep falls
    /// monotonically as this rises, so the value is set by what it costs
    /// rather than by where it stops helping:
    ///
    ///     gain   shortfall   path length   unplaced
    ///        0     985.8 m       23684 m          1
    ///        3     661.3 m       24313 m          0
    ///        8     487.6 m       24520 m          0
    ///       12     408.2 m       24641 m          0
    ///       20     330.1 m       24546 m          1
    ///
    /// 12 is the last point that still fits the whole program: past it the
    /// penalty starts outbidding placement itself and an item goes unplaced,
    /// which is a worse plan than a close one. Paths grow 4% along the way —
    /// the real cost of keeping things apart, and a deliberate trade.
    ///
    /// 0 under `.frozen`, which is the flat penalty the fixtures are pinned
    /// against: the policy covers how a shortfall is *weighed* as well as how
    /// it is measured, because changing only the measurement still moves every
    /// fixture.
    /// 0 under `.frozen`, which is the flat pull the fixtures are pinned
    /// against. Chosen by the same method as its separation counterpart — a
    /// sweep, with the counter-metric being how far the pool ends up from the
    /// house and how many adjacency warnings survive.
    private static func adjacencyExcessGain(_ policy: Constraints.SeparationPolicy) -> Double {
        switch policy {
        case .frozen: return 0
        // Swept on eight plans, measuring how far the pool ends up from the
        // house: 35 m worst case flat, 29 m at this value, and no further
        // improvement past it.
        case .corrected: return 6
        }
    }

    private static func separationShortfallGain(_ policy: Constraints.SeparationPolicy) -> Double {
        switch policy {
        case .frozen: return 0
        case .corrected: return 12
        }
    }

    /// Belong on/right at the water and are the only types allowed inside the
    /// waterfront strip — everything else is excluded from it. Public because
    /// placement *drops* these when the plot has no waterfront, and a UI that
    /// offers them needs to be able to say so rather than let them vanish.
    public static let waterLovingTypes: Set<String> = ["dock", "micro-hydro"]

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
        seed: Int,
        region: RegulatoryRegion = .generic,
        policy: Constraints.SeparationPolicy = .corrected
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

        /// Where the plan enters the plot. The same function `PathsAndFences`
        /// routes the driveway to, so the garage is pulled toward the point
        /// the drive will actually arrive from rather than a guess at it.
        func gate(_ house: Transform?) -> Point? {
            guard let house else { return nil }
            return PathsAndFences.findGatePoint(
                boundary: plot.boundary,
                houseCenter: house.center,
                waterfrontBounds: waterfrontBounds
            )
        }

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

            // A pier runs out from the bank, not along it. The generic search
            // treats a dock like any other box: it tried both orientations,
            // scored them on access and sun like a shed, and parked a 2.5 x 6
            // pier broadside in the middle of the river with a path walking up
            // to its long edge. Where a dock goes is not a search problem — it
            // is determined by which edge the water is on.
            if item.typeId == "dock", policy == .corrected,
               let water = waterfrontBounds, let waterfront = plot.waterfront, let bounds = plot.bounds {
                let long = max(width, height)
                let narrow = min(width, height)
                let reach = min(long, (waterfront.edge == .north || waterfront.edge == .south ? water.height : water.width) * 0.9)
                let anchor = houseCenter ?? Transform(x: bounds.midX, y: bounds.midY, width: 0, height: 0)

                let transform: Transform
                switch waterfront.edge {
                case .north:
                    transform = Transform(
                        x: clamp(anchor.x, bounds.minX + narrow / 2, bounds.maxX - narrow / 2),
                        y: water.maxY - reach / 2,
                        width: narrow, height: reach
                    )
                case .south:
                    transform = Transform(
                        x: clamp(anchor.x, bounds.minX + narrow / 2, bounds.maxX - narrow / 2),
                        y: water.minY + reach / 2,
                        width: narrow, height: reach
                    )
                case .west:
                    transform = Transform(
                        x: water.maxX - reach / 2,
                        y: clamp(anchor.y, bounds.minY + narrow / 2, bounds.maxY - narrow / 2),
                        width: reach, height: narrow
                    )
                case .east:
                    transform = Transform(
                        x: water.minX + reach / 2,
                        y: clamp(anchor.y, bounds.minY + narrow / 2, bounds.maxY - narrow / 2),
                        width: reach, height: narrow
                    )
                }

                var metadata = item.metadata
                metadata["rationaleTokens"] = .array([.string("onWater")])
                placed.append(PlanObject(
                    id: "obj-\(item.typeId)-\(placed.count)-\(Int(floor(rand.next() * 1e6)))",
                    typeId: item.typeId,
                    category: entry.category,
                    transform: transform,
                    label: entry.label,
                    locked: false,
                    layerId: entry.category,
                    metadata: metadata
                ))
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
                rand: rand, layout: layout, avoidBounds: avoidBounds, region: region,
                policy: policy, gate: gate(houseCenter)
            )
            for shrink in [0.8, 0.6, 0.45] {
                if best != nil { break }
                best = searchBestCandidate(
                    plot: plot, bounds: searchBounds, step: step, width: width * shrink, height: height * shrink,
                    entry: entry, placed: placed, houseCenter: houseCenter, weights: weights,
                    rand: rand, layout: layout, avoidBounds: avoidBounds, region: region,
                    policy: policy, gate: gate(houseCenter)
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

    /// How hard the garage is pulled toward the gate. Swept on eight plans:
    /// 19.6 m from the gate with no pull, 13.8 m with it, and flat from a
    /// pull of 1 upward — past that the setback from the boundary and the
    /// house's own road-facing bias are what bind, not this.
    private static let garageGatePull = 2.0

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
        avoidBounds: Rect?,
        region: RegulatoryRegion,
        policy: Constraints.SeparationPolicy,
        gate: Point?
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

                    let hardViolation = Constraints.all(for: region, policy: policy).contains { constraint in
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
                            return Constraints.separation(transform, other.transform, policy) < minDistance
                        }
                    }
                    if hardViolation { continue }

                    let candidate = scoreCandidate(
                        transform: transform, entry: entry, placed: placed, houseCenter: houseCenter,
                        bounds: bounds, weights: weights, boundary: plot.boundary, layout: layout, plot: plot,
                        region: region, policy: policy, gate: gate
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
        plot: Plot,
        region: RegulatoryRegion,
        policy: Constraints.SeparationPolicy,
        gate: Point?
    ) -> (score: Double, reasons: [String]) {
        var score = 0.0
        var reasons: [String] = []

        // You park where you come in. Left to the generic scoring the garage
        // drifted about 20 m inside the boundary on every seed, which is a
        // driveway across half the plot to reach a building whose whole job
        // is to be next to the road.
        if policy == .corrected, entry.id == "garage", let gate {
            score -= distance(transform.center, gate) * garageGatePull
            reasons.append("byTheGate")
        }

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

        for setback in Constraints.boundarySetbacks(for: region) {
            guard Constraints.matches(entry, setback.appliesTo) else { continue }
            guard let d = Constraints.boundaryClearance(transform, boundary: boundary, policy) else { continue }
            if d < setback.minDistanceM {
                score -= (setback.minDistanceM - d) * weights.separation * 2
            } else {
                reasons.append("boundaryClear")
            }
        }

        for constraint in Constraints.all(for: region, policy: policy) {
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
                let d = Constraints.separation(transform, other.transform, policy)
                if (constraint.kind == .separation || constraint.kind == .safety),
                   let minDistance = constraint.minDistance, d < minDistance {
                    // Superlinear in the shortfall, so the penalty says what
                    // the rule means: missing a 12 m separation by a metre is
                    // a mild preference, and putting the pool against the goat
                    // pen is decisive. Under `.frozen` the gain is 0 and this
                    // reduces to the web app's flat penalty, where those two
                    // differ only by a factor of twelve — which a single
                    // strong access or sun pull outbids either way.
                    let shortfall = minDistance - d
                    let severity = 1 + (shortfall / minDistance) * separationShortfallGain(policy)
                    score -= shortfall * weights.separation * severity
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
                        // Superlinear, for the same reason separations are:
                        // a pump 2 m past its limit is a preference, a solar
                        // array at four times the limit is a cable run nobody
                        // would pay for. Flat, the pull loses every argument
                        // with a separation and things that belong together
                        // end up scattered — which is why every plan carried
                        // "far from the battery room" warnings it could have
                        // avoided.
                        let excess = d - maxDistance
                        let severity = 1 + (excess / maxDistance) * adjacencyExcessGain(policy)
                        score -= excess * adjacencyPull * 1.8 * severity
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
