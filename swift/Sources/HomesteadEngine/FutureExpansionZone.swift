import Foundation

/// Ported from the `buildFutureExpansionZone` helper at the bottom of
/// `src/engine/generate.ts`. Deterministic and RNG-free: scans a grid of
/// candidate positions (favouring corners) at shrinking sizes, trying both
/// the plot's aspect ratio and its 90°-rotated counterpart, since leftover
/// space after greedy placement is often a narrow strip rather than
/// plot-shaped.
public enum FutureExpansionZone {
    public static func build(plot: Plot, objects: [PlanObject], mode: PlanningMode) -> [Zone] {
        guard mode != .productionMax else { return [] }
        guard let bounds = plot.bounds else { return [] }
        let plotArea = Polygon.area(plot.boundary)
        let reserveShare: Double = mode == .safetyFirst ? 0.06 : mode == .beautyBalanced ? 0.08 : 0.1
        let baseAspect = bounds.width / max(1, bounds.height)

        for shrink in [1.0, 0.7, 0.5, 0.35, 0.2] {
            let targetArea = plotArea * reserveShare * shrink
            for aspect in [baseAspect, 1 / baseAspect] {
                let w = (targetArea * aspect).squareRoot()
                let h = targetArea / w
                guard w >= 2, h >= 2, w <= bounds.width, h <= bounds.height else { continue }

                let stepX = max(1, (bounds.width - w) / 10)
                let stepY = max(1, (bounds.height - h) / 10)
                var candidates: [Point] = []
                var x = bounds.minX + w / 2
                while x <= bounds.maxX - w / 2 + 0.01 {
                    var y = bounds.minY + h / 2
                    while y <= bounds.maxY - h / 2 + 0.01 {
                        candidates.append(Point(x: x, y: y))
                        y += stepY
                    }
                    x += stepX
                }
                // Prefer positions closer to a corner (reads as a "reserved
                // edge"). JavaScript's sort is stable; Swift's is not, and
                // ties (equidistant candidates) are routine on a symmetric
                // grid, so this carries an explicit index tie-break.
                let ordered = candidates.enumerated().sorted { lhs, rhs in
                    let l = cornerDistance(lhs.element, bounds)
                    let r = cornerDistance(rhs.element, bounds)
                    if l != r { return l < r }
                    return lhs.offset < rhs.offset
                }.map(\.element)

                for c in ordered {
                    // Independent min/max expressions, matching TypeScript's
                    // object literal exactly — see Rect's doc comment.
                    let aabb = Rect(minX: c.x - w / 2, minY: c.y - h / 2, maxX: c.x + w / 2, maxY: c.y + h / 2)
                    let transform = Transform(x: c.x, y: c.y, width: w, height: h, rotationDeg: 0)
                    guard Polygon.contains(transform, polygon: plot.boundary) else { continue }
                    let overlaps = objects.contains { aabb.overlaps($0.transform.aabb, margin: 1) }
                    if overlaps { continue }
                    return [
                        Zone(
                            id: "zone-future-expansion",
                            category: .futureExpansion,
                            boundary: [
                                Point(x: aabb.minX, y: aabb.minY),
                                Point(x: aabb.maxX, y: aabb.minY),
                                Point(x: aabb.maxX, y: aabb.maxY),
                                Point(x: aabb.minX, y: aabb.maxY),
                            ],
                            label: "Future Expansion",
                            metadata: ["reservedForm": .string("user-defined future use")],
                            locked: false
                        ),
                    ]
                }
            }
        }
        return []
    }

    private static func cornerDistance(_ p: Point, _ bounds: Rect) -> Double {
        let corners = [
            Point(x: bounds.minX, y: bounds.minY),
            Point(x: bounds.maxX, y: bounds.minY),
            Point(x: bounds.minX, y: bounds.maxY),
            Point(x: bounds.maxX, y: bounds.maxY),
        ]
        return corners.map { distance($0, p) }.min()!
    }
}
