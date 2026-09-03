import Foundation

/// Ported from `src/engine/pathsAndFences.ts`. Pure and non-random: paths and
/// fences are derived entirely from where objects already landed, so this can
/// be verified directly against the 48 golden fixtures' recorded `paths` and
/// `fences` — no separate isolated fixture needed, unlike `Placement`.
public enum PathsAndFences {
    /// The "gate" is where the plot boundary is crossed to reach the house:
    /// the boundary edge with the largest average y (the south/road-facing
    /// convention `Placement`'s house-siting bias also uses), at the point on
    /// it closest to the house. A waterfront edge is skipped even if it would
    /// otherwise win — a driveway can't cross a river or lake.
    public static func findGatePoint(boundary: [Point], houseCenter: Point, waterfrontBounds: Rect?) -> Point {
        var bestEdge: (Point, Point)?
        var bestY = -Double.infinity
        for i in boundary.indices {
            let a = boundary[i]
            let b = boundary[(i + 1) % boundary.count]
            let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if let waterfrontBounds, pointInWaterfront(mid, waterfrontBounds) { continue }
            if mid.y > bestY {
                bestY = mid.y
                bestEdge = (a, b)
            }
        }
        guard let bestEdge else { return houseCenter }
        return Polygon.project(houseCenter, onto: bestEdge.0, bestEdge.1)
    }

    /// Both boxes are axis-aligned rects in the same plot coordinate system,
    /// so a plain inclusive bounds check is exact — no need for general
    /// point-in-polygon, which is flaky for a point sitting exactly on a
    /// shared edge, as this one deliberately does.
    private static func pointInWaterfront(_ p: Point, _ b: Rect) -> Bool {
        let eps = 1e-6
        return p.x >= b.minX - eps && p.x <= b.maxX + eps && p.y >= b.minY - eps && p.y <= b.maxY + eps
    }

    /// Nearest point on an object's own footprint to an external point —
    /// paths anchor to a building's edge, not its centre, so a stroke doesn't
    /// visually run into the middle of a house or a large field.
    private static func edgePoint(_ transform: Transform, toward: Point) -> Point {
        transform.aabb.nearestPoint(to: toward)
    }

    /// `p1`–`p2` is always axis-aligned here (one leg of an L-shaped route),
    /// so "does this leg cut through that box" reduces to a 1D overlap check
    /// instead of a general segment/rect intersection.
    private static func legHitsBox(_ p1: Point, _ p2: Point, _ box: Rect) -> Bool {
        if abs(p1.y - p2.y) < 1e-6 {
            if p1.y <= box.minY || p1.y >= box.maxY { return false }
            let xMin = min(p1.x, p2.x)
            let xMax = max(p1.x, p2.x)
            return xMax > box.minX && xMin < box.maxX
        }
        if p1.x <= box.minX || p1.x >= box.maxX { return false }
        let yMin = min(p1.y, p2.y)
        let yMax = max(p1.y, p2.y)
        return yMax > box.minY && yMin < box.maxY
    }

    /// Two-segment orthogonal route from `a` to `b`, elbowed at whichever of
    /// the two possible corners crosses fewer other objects' footprints —
    /// real garden paths bend around zones instead of cutting a straight
    /// diagonal across the whole plot. A lightweight stand-in for real
    /// pathfinding (MVP simplification, per PRD §13), but a large
    /// improvement over one raw segment.
    private static func routeAround(_ a: Point, _ b: Point, obstacles: [Rect]) -> [Point] {
        if abs(a.x - b.x) < 0.3 || abs(a.y - b.y) < 0.3 { return [a, b] }
        let elbowViaB = Point(x: b.x, y: a.y)
        let elbowViaA = Point(x: a.x, y: b.y)
        func crossings(_ elbow: Point) -> Int {
            obstacles.reduce(0) { count, box in
                count + (legHitsBox(a, elbow, box) ? 1 : 0) + (legHitsBox(elbow, b, box) ? 1 : 0)
            }
        }
        let elbow = crossings(elbowViaB) <= crossings(elbowViaA) ? elbowViaB : elbowViaA
        return [a, elbow, b]
    }

    /// MVP simplification: paths route around obstacles with a single elbow,
    /// not a full pathfinder — acceptable per PRD §13. The driveway (gate →
    /// garage, wide/paved) and entrance walk (gate → house, narrower) are
    /// distinguished from the narrower garden paths to other
    /// frequently-visited zones.
    public static func synthesizePaths(objects: [PlanObject], plot: Plot) -> [PathEntity] {
        guard let house = objects.first(where: { ObjectLibrary.houseTypeIDs.contains($0.typeId) }) else { return [] }
        let houseCenter = house.transform.center
        let gate = findGatePoint(boundary: plot.boundary, houseCenter: houseCenter, waterfrontBounds: WaterfrontModel.bounds(of: plot))
        let garage = objects.first { $0.typeId == "garage" }
        var paths: [PathEntity] = []

        func boxesExcept(_ ids: Set<String>) -> [Rect] {
            objects.filter { !ids.contains($0.id) }.map(\.transform.aabb)
        }

        if let garage, distance(gate, houseCenter) > 0.5 {
            let garageEdge = edgePoint(garage.transform, toward: gate)
            paths.append(PathEntity(
                id: "path-driveway",
                points: routeAround(gate, garageEdge, obstacles: boxesExcept([garage.id])),
                widthM: 3,
                surfaceType: .paved,
                category: .service
            ))
        }

        let houseGateEdge = edgePoint(house.transform, toward: gate)
        paths.append(PathEntity(
            id: "path-entrance",
            points: routeAround(gate, houseGateEdge, obstacles: boxesExcept([house.id])),
            widthM: 1.4,
            surfaceType: .paved,
            category: .access
        ))

        for object in objects {
            if ObjectLibrary.houseTypeIDs.contains(object.typeId) || object.typeId == "garage" { continue }
            guard let entry = ObjectLibrary[object.typeId], entry.needsAccess else { continue }
            if object.metadata["roofMounted"]?.boolValue == true { continue }
            let objectEdge = edgePoint(object.transform, toward: houseCenter)
            let houseEdge = edgePoint(house.transform, toward: objectEdge)
            paths.append(PathEntity(
                id: "path-\(object.id)",
                points: routeAround(houseEdge, objectEdge, obstacles: boxesExcept([house.id, object.id])),
                widthM: 1.1,
                surfaceType: .gravel,
                category: .access
            ))
        }
        return paths
    }

    public static func synthesizeFences(objects: [PlanObject], plot: Plot) -> [Fence] {
        var fences: [Fence] = [
            Fence(id: "fence-perimeter", points: plot.boundary, fenceType: .perimeter, gated: true),
        ]
        for object in objects {
            guard let entry = ObjectLibrary[object.typeId], entry.requiresFence else { continue }
            let aabb = object.transform.aabb
            let pad = 0.6
            let fenceType: FenceType = entry.category == .animal ? .paddock : entry.category == .water ? .decorative : .garden
            fences.append(Fence(
                id: "fence-\(object.id)",
                points: [
                    Point(x: aabb.minX - pad, y: aabb.minY - pad),
                    Point(x: aabb.maxX + pad, y: aabb.minY - pad),
                    Point(x: aabb.maxX + pad, y: aabb.maxY + pad),
                    Point(x: aabb.minX - pad, y: aabb.maxY + pad),
                ],
                fenceType: fenceType,
                gated: false
            ))
        }
        return fences
    }
}
