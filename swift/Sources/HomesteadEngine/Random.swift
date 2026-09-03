/// The seeded generator every placement decision is downstream of.
///
/// Ported from `src/engine/placement.ts`. JavaScript reaches 32-bit semantics
/// through `| 0`, `>>> n` and `Math.imul`; the same bit patterns come out of
/// doing the arithmetic in `UInt32` with wrapping operators. Promoting any of
/// this to `Int` changes the stream, and with it every layout the planner
/// produces — `Tests/HomesteadEngineTests/RandomTests.swift` pins it against
/// draws taken from the TypeScript implementation itself.
public struct Mulberry32 {
    private var state: UInt32

    public init(seed: Int) {
        // `a |= 0` in the original: the seed is reinterpreted as a 32-bit
        // pattern rather than clamped.
        state = UInt32(bitPattern: Int32(truncatingIfNeeded: seed))
    }

    /// The next draw in `[0, 1)`.
    public mutating func next() -> Double {
        state = state &+ 0x6d2b_79f5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}
