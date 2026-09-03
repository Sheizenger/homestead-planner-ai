import Testing
@testable import HomesteadEngine

private struct RandomFixture: Decodable {
    let mulberry32: [String: [Double]]
}

/// Every placed object is downstream of this stream, so it is pinned against
/// draws taken from the TypeScript generator itself rather than against
/// values reasoned out by hand. Divergence here would surface later as 48
/// mismatched layouts with no obvious cause.
@Test func mulberry32ReproducesTheTypeScriptStream() throws {
    let fixture = try Fixtures.decode(RandomFixture.self, from: "rng.json")
    #expect(!fixture.mulberry32.isEmpty)

    for (seed, expected) in fixture.mulberry32 {
        var rng = Mulberry32(seed: Int(seed)!)
        let actual = (0..<expected.count).map { _ in rng.next() }
        #expect(actual == expected, "stream diverged for seed \(seed)")
    }
}
