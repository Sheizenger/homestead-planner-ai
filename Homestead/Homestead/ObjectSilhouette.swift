//
//  ObjectSilhouette.swift
//  Homestead
//
//  The outline of an object *as drawn* in the axonometric view, in screen
//  space.
//
//  The first pass used the footprint for both selection and hit testing, which
//  in a view with height is the wrong shape in the wrong place: the footprint
//  projects to a flat diamond at the bottom of the building, so clicking the
//  walls or the roof — the whole of what you can actually see — missed, and
//  the selection ring was drawn on the ground under the thing it was
//  selecting.
//
//  Every massing this view draws is convex (a gabled or gambrel house, a box,
//  a cylinder, a bed), so the convex hull of its projected vertices is its
//  silhouette exactly. A grove is not convex, but a hull around it is the
//  right selection target anyway: it is a zone, not an object with a shape.
//

import SwiftUI
import HomesteadEngine

enum Silhouette {
    /// World points, with elevation, whose projection bounds the object.
    /// Includes the roof overhang, because that is part of what is drawn and
    /// therefore part of what a click should find.
    static func hullPoints(for object: PlanObject, base: Double) -> [(Point, Double)] {
        let corners = object.transform.corners
        guard corners.count == 4 else { return [] }
        let centre = object.transform.center
        let width = object.transform.width
        let depth = object.transform.height
        let run = min(width, depth) / 2
        let overhang = min(0.45, run * 0.22)

        /// The footprint pushed out by `amount` on every side.
        func expanded(by amount: Double) -> [Point] {
            corners.map { corner in
                Point(
                    x: corner.x + (corner.x >= centre.x ? amount : -amount),
                    y: corner.y + (corner.y >= centre.y ? amount : -amount)
                )
            }
        }

        /// The two ends of the ridge, which runs along the longer axis and
        /// oversails the gables by the same verge as the eaves.
        func ridgeEnds() -> [Point] {
            let alongX = width >= depth
            let half = (alongX ? width : depth) / 2 + overhang
            return alongX
                ? [Point(x: centre.x - half, y: centre.y), Point(x: centre.x + half, y: centre.y)]
                : [Point(x: centre.x, y: centre.y - half), Point(x: centre.x, y: centre.y + half)]
        }

        var points: [(Point, Double)] = corners.map { ($0, base) }

        switch Massing.form(for: object) {
        case let .gabled(eaves, ridge), let .glass(eaves, ridge):
            points += expanded(by: overhang).map { ($0, base + eaves) }
            points += ridgeEnds().map { ($0, base + ridge) }

        case let .gambrel(eaves, knuckle, ridge):
            points += expanded(by: overhang).map { ($0, base + eaves) }
            points += expanded(by: -run * 0.45).map { ($0, base + knuckle) }
            points += ridgeEnds().map { ($0, base + ridge) }

        case let .block(height), let .flat(height), let .rows(height, _), let .panels(height):
            points += corners.map { ($0, base + height) }

        case .basin:
            // The water sits below grade, so the silhouette is the coping.
            points += corners.map { ($0, base + 0.16) }

        case .deck:
            points += corners.map { ($0, base + 0.55) }

        case let .cylinder(height, radiusScale):
            // A circle, not the square it is inscribed in: a tank's silhouette
            // is noticeably narrower than its footprint.
            let radius = min(width, depth) * radiusScale
            for step in 0..<12 {
                let angle = Double(step) / 12 * 2 * .pi
                let rim = Point(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                points.append((rim, base))
                points.append((rim, base + height))
            }

        case let .canopy(height, radius, _):
            for position in Massing.grovePositions(for: object) {
                for step in 0..<6 {
                    let angle = Double(step) / 6 * 2 * .pi
                    let rim = Point(x: position.x + cos(angle) * radius, y: position.y + sin(angle) * radius)
                    points.append((rim, base))
                    points.append((rim, base + height))
                }
            }
        }
        return points
    }

    /// The silhouette as a closed screen-space path, or an empty array when
    /// the object has nothing to draw.
    ///
    /// The hull and the containment test both come from `Polygon`, where they
    /// are covered by tests that run here — this layer can only be built on a
    /// Mac, so every piece of geometry that can live in the engine should.
    static func path(for object: PlanObject, base: Double, project: (Point, Double) -> CGPoint) -> [CGPoint] {
        let projected = hullPoints(for: object, base: base).map { world, z -> Point in
            let screen = project(world, z)
            return Point(x: Double(screen.x), y: Double(screen.y))
        }
        return Polygon.convexHull(projected).map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// True when the click landed inside the outline — which is the whole
    /// point of having the outline.
    static func contains(_ point: CGPoint, in hull: [CGPoint]) -> Bool {
        guard hull.count > 2 else { return false }
        return Polygon.contains(
            Point(x: Double(point.x), y: Double(point.y)),
            polygon: hull.map { Point(x: Double($0.x), y: Double($0.y)) }
        )
    }
}
