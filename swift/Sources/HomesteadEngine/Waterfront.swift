import Foundation

/// Ported from `src/engine/waterfront.ts`. The waterfront strip is modelled
/// as a slice of the plot itself — inset from one boundary edge by
/// `widthM` — rather than land beyond the property line, matching how rural
/// river/lake/pond frontage usually works and reusing the existing
/// polygon/placement machinery for free.
public enum WaterfrontModel {
    public static func bounds(of plot: Plot) -> Rect? {
        guard let wf = plot.waterfront, let b = plot.bounds else { return nil }
        let span = (wf.edge == .north || wf.edge == .south) ? b.height : b.width
        let width = max(0, min(wf.widthM, span))
        // Each case reuses two of the plot's own edges verbatim and computes
        // the other two — matching TypeScript's independent min/max fields
        // exactly (see Rect's doc comment) rather than deriving an edge from
        // a recombined width, which can differ by a ULP.
        switch wf.edge {
        case .north: return Rect(minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.minY + width)
        case .south: return Rect(minX: b.minX, minY: b.maxY - width, maxX: b.maxX, maxY: b.maxY)
        case .west: return Rect(minX: b.minX, minY: b.minY, maxX: b.minX + width, maxY: b.maxY)
        case .east: return Rect(minX: b.maxX - width, minY: b.minY, maxX: b.maxX, maxY: b.maxY)
        }
    }

    /// A slice of the plot boundary itself, clipped so the water never
    /// renders outside the property even when the bounding-box-derived strip
    /// would spill past a non-rectangular (e.g. L-shaped) boundary.
    public static func zone(of plot: Plot) -> Zone? {
        guard let wf = plot.waterfront, let bounds = bounds(of: plot) else { return nil }
        let clipped = Polygon.clip(plot.boundary, to: bounds)
        let boundary = clipped.count >= 3 ? clipped : [
            Point(x: bounds.minX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.maxY),
            Point(x: bounds.minX, y: bounds.maxY),
        ]
        return Zone(
            id: "zone-waterfront",
            category: .water,
            boundary: boundary,
            label: wf.type.rawValue,
            metadata: ["waterfrontType": .string(wf.type.rawValue)],
            locked: true
        )
    }

    // MARK: - The waterline

    /// The most water can be taken away from the planning strip, as a
    /// fraction of its width.
    ///
    /// The strip `bounds` returns is what the placer reserves, and the dock
    /// is sited against it: a pier starts at the landward edge and reaches
    /// 90% of the way across. So the drawn waterline may wander inside the
    /// strip — that is the whole point of having one — but it must never take
    /// so much that a pier ends up over dry land. Leaving 55% wet everywhere
    /// keeps a 90% pier in water whatever shape the bank is.
    public static let minimumOpenWater = 0.55

    /// How far the bank sits inside the strip at `t` along the frontage, as a
    /// fraction of the strip's width. Zero is a bank right on the planning
    /// line; larger means more land, less water.
    ///
    /// This is the whole of what makes the three kinds of water look like
    /// three kinds of water rather than one blue rectangle with a different
    /// word printed on it, which is what they were.
    public static func bankProfile(_ type: WaterfrontType, at t: Double) -> Double {
        let along = min(max(t, 0), 1)
        switch type {
        case .river:
            // A channel of roughly even width that wanders: the bank is never
            // straight, and never far from where the strip says it is.
            return 0.09 + 0.06 * sin(along * 2 * .pi * 1.5 + 0.6)
        case .lake:
            // One broad bay, open at the middle and closing toward the ends —
            // an expanse the plot happens to meet, not a channel.
            return 0.22 * (1 - sin(along * .pi))
        case .pond:
            // A rounded body: the bank comes right in at both ends, leaving a
            // lens rather than a band.
            return 0.06 + 0.36 * (1 - pow(sin(along * .pi), 0.55))
        }
    }

    /// The water as it is actually drawn: the strip with its landward edge
    /// replaced by a bank that belongs to this kind of water.
    ///
    /// Only the two views read this. `bounds` — which the placer, the dock
    /// and the fences all use, and which thirteen fixtures pin — is untouched
    /// and stays a rectangle.
    public static func shoreline(of plot: Plot, samples: Int = 48) -> [Point]? {
        guard let waterfront = plot.waterfront, let water = bounds(of: plot), samples >= 2 else { return nil }
        let horizontal = waterfront.edge == .north || waterfront.edge == .south
        let width = horizontal ? water.height : water.width
        guard width > 0, water.width > 0, water.height > 0 else { return nil }

        let budget = min(1 - minimumOpenWater, 1.0)
        var bank: [Point] = []
        for step in 0...samples {
            let along = Double(step) / Double(samples)
            let pullback = min(max(bankProfile(waterfront.type, at: along), 0), budget) * width
            switch waterfront.edge {
            case .north:
                bank.append(Point(x: water.minX + along * water.width, y: water.maxY - pullback))
            case .south:
                bank.append(Point(x: water.maxX - along * water.width, y: water.minY + pullback))
            case .west:
                bank.append(Point(x: water.maxX - pullback, y: water.maxY - along * water.height))
            case .east:
                bank.append(Point(x: water.minX + pullback, y: water.minY + along * water.height))
            }
        }

        // The three sides that are the property line, then back along the bank.
        let outer: [Point]
        switch waterfront.edge {
        case .north: outer = [Point(x: water.maxX, y: water.minY), Point(x: water.minX, y: water.minY)]
        case .south: outer = [Point(x: water.minX, y: water.maxY), Point(x: water.maxX, y: water.maxY)]
        case .west: outer = [Point(x: water.minX, y: water.minY), Point(x: water.minX, y: water.maxY)]
        case .east: outer = [Point(x: water.maxX, y: water.maxY), Point(x: water.maxX, y: water.minY)]
        }

        let polygon = bank + outer
        // Clipped the same way `zone` is, so water never renders outside the
        // property on a notched or L-shaped plot.
        let clipped = Polygon.clip(polygon, to: water)
        return clipped.count >= 3 ? clipped : polygon
    }

    /// The dry part of the planning strip: the land between the waterline and
    /// the line the placer measures setbacks from.
    ///
    /// The bank has to be the strip *minus* the water, not the whole strip.
    /// The water surface sits below grade, so a bank drawn across the whole
    /// strip is an opaque lid over it — in a renderer with a depth buffer the
    /// river simply disappears under a sandbank, which is what happened.
    public static func bank(of plot: Plot, samples: Int = 48) -> [Point]? {
        guard let waterfront = plot.waterfront,
              let water = bounds(of: plot),
              let shore = shoreline(of: plot, samples: samples), shore.count > 2 else { return nil }
        // `shoreline` walks the waterline first and then closes along the
        // property line; the bank closes the other way, along the landward
        // edge of the strip.
        let waterline = Array(shore.prefix(samples + 1))
        let landward: [Point]
        switch waterfront.edge {
        case .north: landward = [Point(x: water.maxX, y: water.maxY), Point(x: water.minX, y: water.maxY)]
        case .south: landward = [Point(x: water.minX, y: water.minY), Point(x: water.maxX, y: water.minY)]
        case .west: landward = [Point(x: water.maxX, y: water.maxY), Point(x: water.maxX, y: water.minY)]
        case .east: landward = [Point(x: water.minX, y: water.minY), Point(x: water.minX, y: water.maxY)]
        }
        return waterline + landward
    }

    /// Rough planning thresholds for a small run-of-river or drop-based
    /// micro-hydro setup — not a substitute for a real hydrology assessment.
    public static let minHydroFlowMps: Double = 0.5
    public static let minHydroDropM: Double = 1

    public static func isHydroFeasible(_ plot: Plot) -> Bool {
        guard let wf = plot.waterfront else { return false }
        return (wf.flowSpeedMps ?? 0) >= minHydroFlowMps || (wf.elevationDropM ?? 0) >= minHydroDropM
    }
}
