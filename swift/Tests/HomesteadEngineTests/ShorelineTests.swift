import Testing
import Foundation
@testable import HomesteadEngine

/// River, lake and pond drew the identical blue rectangle with a different
/// word printed on it — "формат воды везде одинаковый какой бы я не выбрал".
/// These pin that they are now three shapes, and that being three shapes has
/// not broken the one thing the strip is load-bearing for.
struct ShorelineTests {
    private func plot(_ type: WaterfrontType, edge: PlotEdge = .north, width: Double = 12) -> Plot {
        Plot(
            boundary: [
                Point(x: 0, y: 0), Point(x: 60, y: 0),
                Point(x: 60, y: 45), Point(x: 0, y: 45),
            ],
            waterfront: Waterfront(type: type, edge: edge, widthM: width)
        )
    }

    @Test func theThreeKindsAreThreeDifferentShapes() {
        let shapes = WaterfrontType.allCases.map { WaterfrontModel.shoreline(of: plot($0)) }
        for shape in shapes { #expect(shape?.count ?? 0 > 3) }
        for (a, b) in [(0, 1), (0, 2), (1, 2)] {
            #expect(shapes[a] != shapes[b])
        }
    }

    /// The property of the river that makes it a river: a channel of roughly
    /// even width, wandering rather than ruled.
    @Test func theRiverIsAWanderingChannelOfEvenWidth() {
        let widths = (0...40).map { WaterfrontModel.bankProfile(.river, at: Double($0) / 40) }
        let spread = widths.max()! - widths.min()!
        #expect(spread > 0.05, "a straight bank is what this is replacing")
        #expect(spread < 0.2, "a river should not pinch to a puddle")
        // It actually goes both ways rather than sloping off in one
        // direction, which would read as a wedge.
        let middle = (widths.max()! + widths.min()!) / 2
        #expect(widths.contains { $0 > middle } && widths.contains { $0 < middle })
    }

    /// The lake is open in the middle and closes toward the ends; the pond
    /// does the same thing far harder, which is what makes one an expanse and
    /// the other a body of water.
    @Test func theLakeOpensAtTheMiddleAndThePondIsALens() {
        for type in [WaterfrontType.lake, .pond] {
            let middle = WaterfrontModel.bankProfile(type, at: 0.5)
            let end = WaterfrontModel.bankProfile(type, at: 0)
            #expect(middle < end)
        }
        let lakeTaper = WaterfrontModel.bankProfile(.lake, at: 0) - WaterfrontModel.bankProfile(.lake, at: 0.5)
        let pondTaper = WaterfrontModel.bankProfile(.pond, at: 0) - WaterfrontModel.bankProfile(.pond, at: 0.5)
        #expect(pondTaper > lakeTaper * 1.5)
    }

    /// The load-bearing one. The dock is sited against `bounds` — a pier from
    /// the landward edge reaching 90% across — so a bank that ate more than
    /// 45% of the strip anywhere would leave a pier standing on dry land.
    @Test func noBankEverStrandsAPier() {
        for type in WaterfrontType.allCases {
            for step in 0...200 {
                let pullback = WaterfrontModel.bankProfile(type, at: Double(step) / 200)
                #expect(pullback >= 0)
                #expect(pullback <= 1 - WaterfrontModel.minimumOpenWater)
            }
        }
        #expect(WaterfrontModel.minimumOpenWater > 0.9 * 0.55)
    }

    /// The planning strip is untouched, whatever the drawn water does: it is
    /// what the placer, the fences and thirteen fixtures work from.
    @Test func theStripStaysARectangle() {
        for type in WaterfrontType.allCases {
            #expect(WaterfrontModel.bounds(of: plot(type)) == Rect(minX: 0, minY: 0, width: 60, height: 12))
        }
    }

    /// Every drawn point is inside the strip — the water never spills onto
    /// the land the plan has put buildings on.
    @Test func theWaterStaysInsideTheStrip() {
        for type in WaterfrontType.allCases {
            for edge in PlotEdge.allCases {
                let site = plot(type, edge: edge)
                let strip = WaterfrontModel.bounds(of: site)!
                let shore = WaterfrontModel.shoreline(of: site) ?? []
                #expect(shore.count > 3)
                for point in shore {
                    #expect(point.x >= strip.minX - 1e-9 && point.x <= strip.maxX + 1e-9)
                    #expect(point.y >= strip.minY - 1e-9 && point.y <= strip.maxY + 1e-9)
                }
            }
        }
    }

    /// Whichever edge the water is on, the same fraction of the strip is
    /// wet: the profile runs along the frontage, not along x. The strips
    /// themselves differ — a north frontage on this plot is 60 × 12 and a
    /// west one 12 × 45 — so it is the fraction that has to match.
    @Test func everyEdgeGetsTheSameFractionOfWater() {
        for type in WaterfrontType.allCases {
            let fractions = PlotEdge.allCases.map { edge -> Double in
                let site = plot(type, edge: edge)
                let strip = WaterfrontModel.bounds(of: site)!
                let shore = WaterfrontModel.shoreline(of: site) ?? []
                var total = 0.0
                for index in shore.indices {
                    let a = shore[index]
                    let b = shore[(index + 1) % shore.count]
                    total += a.x * b.y - b.x * a.y
                }
                return abs(total) / 2 / (strip.width * strip.height)
            }
            for fraction in fractions {
                #expect(abs(fraction - fractions[0]) < 1e-9)
                // Real water, not a sliver and not the whole rectangle back.
                #expect(fraction > 0.6 && fraction < 0.99)
            }
        }
    }

    /// What separates the three is not how much bank there is — measured,
    /// the means come out at 0.10, 0.08 and 0.15, close enough that nobody
    /// would tell them apart — but how the bank *moves* along the frontage. A
    /// river wanders a little and often; a lake sweeps once; a pond sweeps
    /// hard enough to close at both ends.
    @Test func eachKindOfWaterMovesItsBankDifferently() {
        func samples(_ type: WaterfrontType) -> [Double] {
            (0...200).map { WaterfrontModel.bankProfile(type, at: Double($0) / 200) }
        }
        func range(_ type: WaterfrontType) -> Double {
            let values = samples(type)
            return values.max()! - values.min()!
        }
        func turns(_ type: WaterfrontType) -> Int {
            let values = samples(type)
            var count = 0
            for index in 1..<(values.count - 1) where
                (values[index] - values[index - 1]) * (values[index + 1] - values[index]) < 0 {
                count += 1
            }
            return count
        }
        #expect(range(.pond) > range(.lake))
        #expect(range(.lake) > range(.river))
        // The river is the only one that changes its mind more than once.
        #expect(turns(.river) >= 3)
        #expect(turns(.lake) == 1)
        #expect(turns(.pond) == 1)
    }

    @Test func noWaterfrontMeansNoShoreline() {
        #expect(WaterfrontModel.shoreline(of: Plot(boundary: [
            Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10),
        ])) == nil)
    }
}
