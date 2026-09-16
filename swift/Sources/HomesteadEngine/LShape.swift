import Foundation

/// The L-shaped house, as a shape rather than a label.
///
/// `ObjectLibrary.Shape` has carried `.lshape` since the port, and nothing
/// anywhere read it — not the placer, not the view, not the silhouette. Ticking
/// "L-shaped" in the brief picked a different catalog id with a different
/// default size and drew the identical box, which is what "L образный дом не
/// строится" was reporting.
///
/// The L is inscribed in the object's own bounding box rather than replacing
/// it. The box stays what the plot reserves — setbacks and separations are
/// measured from it, and the courtyard is the house's own private corner, not
/// somewhere a shed could go — so nothing in the placer or the frozen
/// fixtures moves. What changes is the form standing inside it.
public enum LShape {
    /// How deep each wing is, as a fraction of the box's shorter side.
    ///
    /// This is the number that decides whether the result reads as a house.
    /// Cutting a fraction off each side instead — the obvious first
    /// parameterisation — gives two wings that both run along the *same*
    /// axis: at the catalog's 14 × 11 that is a 14 × 6.4 bar beside an
    /// 8.1 × 4.6 bar, two parallel ridges, which reads as a pair of sheds.
    /// A real L is two elongated wings meeting at a corner with their ridges
    /// perpendicular, and that is what a constant wing *depth* produces:
    /// 14 × 4.95 against 4.95 × 11.
    public static let wingDepthFraction = 0.45

    /// Below a quarter the wings are corridors; above nine tenths there is no
    /// courtyard left and the L is a rectangle with a nick in it.
    public static func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0.25), 0.9)
    }

    public static func wingDepth(of transform: Transform, fraction: Double = wingDepthFraction) -> Double {
        min(transform.width, transform.height) * clampedFraction(fraction)
    }

    /// The two wings, as transforms in the same frame as the object's own —
    /// so each can be built by the ordinary gabled-building routine, and each
    /// rotates with the house.
    ///
    /// `main` is the larger of the two. The wings run along the box's north
    /// and west edges, leaving the courtyard open to the south-east: the
    /// quarter that gets sun from mid-morning until the afternoon, with the
    /// building's own mass between it and the cold side. Every plan puts it
    /// the same way, so two runs of the same brief look the same.
    public static func wings(
        of transform: Transform,
        fraction: Double = wingDepthFraction
    ) -> (main: Transform, cross: Transform) {
        let depth = wingDepth(of: transform, fraction: fraction)
        let halfWidth = transform.width / 2
        let halfHeight = transform.height / 2

        // Along the north edge: full width, one wing deep.
        let along = local(
            transform,
            centre: Point(x: 0, y: -halfHeight + depth / 2),
            width: transform.width,
            height: depth
        )
        // Down the west edge, starting where the north bar ends. The two do
        // not overlap, and that is deliberate: their union is still exactly
        // the L, but a wing buried inside another would emit walls with
        // nothing in front of them. A painter's algorithm sorts whole faces,
        // so a buried wall drawn at its own depth cuts straight across the
        // roof that should be hiding it — the classic way interpenetrating
        // solids fail. Butting the wings instead gives the junction a valley,
        // which is what a cross-gabled house actually has.
        let across = local(
            transform,
            centre: Point(x: -halfWidth + depth / 2, y: depth / 2),
            width: depth,
            height: transform.height - depth
        )
        return along.width * along.height >= across.width * across.height
            ? (along, across)
            : (across, along)
    }

    /// The six corners of the L in world space, wound the same way as
    /// `Transform.corners`.
    ///
    /// This is the outline a click should find and a selection should trace,
    /// and — where a caller wants it — the real area of the thing.
    public static func footprint(of transform: Transform, fraction: Double = wingDepthFraction) -> [Point] {
        let depth = wingDepth(of: transform, fraction: fraction)
        let halfWidth = transform.width / 2
        let halfHeight = transform.height / 2
        let innerX = -halfWidth + depth
        let innerY = -halfHeight + depth
        return [
            Point(x: -halfWidth, y: -halfHeight),
            Point(x: halfWidth, y: -halfHeight),
            Point(x: halfWidth, y: innerY),
            Point(x: innerX, y: innerY),
            Point(x: innerX, y: halfHeight),
            Point(x: -halfWidth, y: halfHeight),
        ].map { world(transform, $0) }
    }

    /// Floor area of the L. Always less than the bounding box, which is why
    /// it is worth having a name — the box is what the plot reserves, this is
    /// what gets built.
    public static func area(of transform: Transform, fraction: Double = wingDepthFraction) -> Double {
        let depth = wingDepth(of: transform, fraction: fraction)
        return transform.width * depth + depth * transform.height - depth * depth
    }

    /// The open corner, for anything that wants to know where the house is
    /// not — planting, a terrace, or simply not putting the front door there.
    public static func courtyard(of transform: Transform, fraction: Double = wingDepthFraction) -> Transform {
        let depth = wingDepth(of: transform, fraction: fraction)
        return local(
            transform,
            centre: Point(x: depth / 2, y: depth / 2),
            width: transform.width - depth,
            height: transform.height - depth
        )
    }

    // MARK: - Object frame to world

    private static func world(_ transform: Transform, _ point: Point) -> Point {
        let radians = transform.rotationDeg * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return Point(
            x: transform.x + point.x * cosine - point.y * sine,
            y: transform.y + point.x * sine + point.y * cosine
        )
    }

    private static func local(_ transform: Transform, centre: Point, width: Double, height: Double) -> Transform {
        let placed = world(transform, centre)
        return Transform(
            x: placed.x,
            y: placed.y,
            width: width,
            height: height,
            rotationDeg: transform.rotationDeg
        )
    }
}
