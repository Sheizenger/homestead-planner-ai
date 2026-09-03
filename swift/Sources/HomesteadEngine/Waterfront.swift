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

    /// Rough planning thresholds for a small run-of-river or drop-based
    /// micro-hydro setup — not a substitute for a real hydrology assessment.
    public static let minHydroFlowMps: Double = 0.5
    public static let minHydroDropM: Double = 1

    public static func isHydroFeasible(_ plot: Plot) -> Bool {
        guard let wf = plot.waterfront else { return false }
        return (wf.flowSpeedMps ?? 0) >= minHydroFlowMps || (wf.elevationDropM ?? 0) >= minHydroDropM
    }
}
