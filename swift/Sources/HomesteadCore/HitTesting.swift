import Foundation
import HomesteadEngine

/// `Canvas` draws pixels, not a view hierarchy — there is no hit-testing to
/// inherit the way an ordinary SwiftUI view stack gets it for free. This
/// reimplements it, and does so correctly for a rotated object: the web
/// app's marquee selection tested only an object's centre point (see
/// BACKLOG.md), which is wrong for anything wider than it is tall once
/// rotated. Both functions here test the object's actual rotated footprint.
public enum HitTesting {
    /// The topmost object under `point` (world space), or `nil`. "Topmost"
    /// is draw order: later entries in `objects` paint over earlier ones, so
    /// the search runs back to front and returns the first hit.
    public static func hitTest(_ point: Point, in objects: [PlanObject]) -> PlanObject.ID? {
        for object in objects.reversed() where Polygon.contains(point, polygon: object.transform.corners) {
            return object.id
        }
        return nil
    }

    /// Every object whose rotated footprint touches `rectangle` (world
    /// space) — a marquee has to catch a corner poking out of the box, not
    /// just an object wholly inside it, so this is a true polygon/rect
    /// overlap rather than an AABB shortcut: an object's AABB can overlap
    /// the marquee while its actual rotated corners sit entirely outside it
    /// (a diamond just clipping a box corner), which would otherwise select
    /// objects the marquee never visually touched.
    public static func objectsIntersecting(_ rectangle: Rect, in objects: [PlanObject]) -> [PlanObject.ID] {
        let marqueeCorners = [
            Point(x: rectangle.minX, y: rectangle.minY),
            Point(x: rectangle.maxX, y: rectangle.minY),
            Point(x: rectangle.maxX, y: rectangle.maxY),
            Point(x: rectangle.minX, y: rectangle.maxY),
        ]
        return objects.filter { object in
            let corners = object.transform.corners
            // A *true* bounding box for the cheap reject — `Transform.aabb`
            // is the placement engine's axis-aligned-only approximation
            // (see its doc comment) and can under-report a freely-rotated
            // object's real extent, which would wrongly reject a hit here.
            guard let trueBounds = Rect(bounding: corners), trueBounds.overlaps(rectangle) else { return false }
            // Either shape has a vertex inside the other, or an edge from
            // one crosses an edge of the other: covers full containment
            // either way plus every partial-overlap case a convex
            // quadrilateral against another convex quadrilateral can make.
            if corners.contains(where: { Polygon.contains($0, polygon: marqueeCorners) }) { return true }
            if marqueeCorners.contains(where: { Polygon.contains($0, polygon: corners) }) { return true }
            for i in corners.indices {
                let a1 = corners[i], a2 = corners[(i + 1) % corners.count]
                for j in marqueeCorners.indices {
                    let b1 = marqueeCorners[j], b2 = marqueeCorners[(j + 1) % marqueeCorners.count]
                    if Polygon.segmentsIntersect(a1, a2, b1, b2) { return true }
                }
            }
            return false
        }.map(\.id)
    }
}
