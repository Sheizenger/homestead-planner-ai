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
import HomesteadCore

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
