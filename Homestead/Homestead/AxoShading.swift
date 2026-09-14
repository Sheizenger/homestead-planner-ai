//
//  AxoShading.swift
//  Homestead
//
//  What makes an axonometric read as built rather than diagrammed: one light
//  for the whole scene, cast shadows on the ground, and materials with a
//  surface. The first pass shaded faces with hand-picked constants — 0.34 for
//  this wall, 0.18 for that roof — which is why every object looked lit by
//  its own private sun and the whole plan read as coloured cardboard.
//
//  Everything here is procedural. Bitmap textures would mean shipping and
//  licensing assets, they blur at the zoom levels this view is used at, and
//  they can't follow the projection the way a pattern drawn in the face's own
//  basis does. Drawn patterns stay crisp at any scale and cost nothing but
//  paths.
//

import SwiftUI
import HomesteadEngine

enum AxoLight {
    /// Direction *to* the sun: north-west and fairly high, which is the
    /// convention isometric illustration uses — it lights the two faces the
    /// viewer can see most of and leaves the near-south wall in shade, so
    /// depth reads without any outline doing the work.
    static let toSun = (x: -0.45, y: -0.55, z: 0.70)

    /// How much of a face's colour survives with no direct light on it.
    /// High, because this is outdoor daylight with sky fill, not a spotlight.
    private static let ambient = 0.55

    /// The brightness a face is painted at when it gets its base colour
    /// untouched. Faces above it are washed toward white, below toward black,
    /// so the palette stays the one `CategoryStyle` chose.
    private static let neutral = 0.78

    /// Lambert term for a face with this outward normal, in [0, 1].
    static func brightness(normal: (x: Double, y: Double, z: Double)) -> Double {
        let length = (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot()
        guard length > 0 else { return ambient }
        let dot = (normal.x * toSun.x + normal.y * toSun.y + normal.z * toSun.z) / length
        return ambient + (1 - ambient) * max(0, dot)
    }

    /// The `shade` value `AxoPainter.face` wants: positive darkens, negative
    /// lightens. Derived from the light rather than chosen by eye, so every
    /// object in the scene agrees about where the sun is.
    static func shade(normal: (x: Double, y: Double, z: Double)) -> Double {
        (neutral - brightness(normal: normal)) * 1.35
    }

    /// Outward normal of a vertical wall whose base runs from `a` to `b`,
    /// with the footprint wound clockwise in screen terms (the order
    /// `Transform.corners` produces).
    static func wallNormal(from a: Point, to b: Point) -> (x: Double, y: Double, z: Double) {
        // Right-hand perpendicular of the edge direction points out of the
        // footprint for this winding.
        (x: b.y - a.y, y: -(b.x - a.x), z: 0)
    }

    /// Outward normal of a roof plane that rises from eaves edge `a`–`b` to a
    /// ridge `rise` metres above, `run` metres horizontally inward.
    static func roofNormal(from a: Point, to b: Point, run: Double, rise: Double) -> (x: Double, y: Double, z: Double) {
        let wall = wallNormal(from: a, to: b)
        let length = (wall.x * wall.x + wall.y * wall.y).squareRoot()
        guard length > 0, run > 0 else { return (0, 0, 1) }
        // Tilt the wall normal up by the pitch: horizontal component scales
        // with the run, vertical with the rise.
        return (x: wall.x / length * rise, y: wall.y / length * rise, z: run)
    }

    static let up = (x: 0.0, y: 0.0, z: 1.0)

    /// Where a point `height` metres up lands on the ground, along the light.
    static func shadowOffset(height: Double) -> Point {
        Point(x: -toSun.x / toSun.z * height, y: -toSun.y / toSun.z * height)
    }
}

/// Deterministic pseudo-randomness. Scatter driven by `Double.random` would
/// re-roll every frame and make the grass crawl; hashing the object's own id
/// and the index of the thing being placed gives the same field every redraw,
/// for free, with no state to keep.
enum AxoNoise {
    static func value(_ seed: String, _ index: Int, _ salt: Int = 0) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        hash = (hash ^ UInt64(bitPattern: Int64(index))) &* 0x1000_0000_01b3
        hash = (hash ^ UInt64(bitPattern: Int64(salt))) &* 0x1000_0000_01b3
        hash ^= hash >> 33
        return Double(hash % 100_000) / 100_000
    }

    /// Symmetric jitter in ±`amount`.
    static func jitter(_ seed: String, _ index: Int, _ salt: Int, _ amount: Double) -> Double {
        (value(seed, index, salt) - 0.5) * 2 * amount
    }
}

/// What a surface is made of. Chosen per object type, because "barn" and
/// "greenhouse" being visibly different materials is most of what makes the
/// two recognisable at a glance — more than their silhouettes, which are the
/// same gabled box.
enum AxoMaterial {
    case shingle
    case metalRoof
    case thatch
    case plank
    case board
    case plaster
    case brick
    case glass
    case none

    /// Spacing of the pattern, in metres.
    var pitch: Double {
        switch self {
        case .shingle: return 0.55
        case .metalRoof: return 0.8
        case .thatch: return 0.7
        case .plank: return 0.42
        case .board: return 0.9
        case .plaster: return 0
        case .brick: return 0.32
        case .glass: return 0
        case .none: return 0
        }
    }
}
