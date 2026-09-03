import Testing
@testable import HomesteadEngine

/// Expected values below are the real `computeWaterfrontBounds`/
/// `isHydroFeasible`/`elevationAt`/`computeContourLines` outputs from Node,
/// not derived by inspection.
struct WaterfrontElevationTests {
    private func plot(waterfront: Waterfront? = nil, elevation: PlotElevation? = nil) -> Plot {
        Plot(boundary: PlotShape.rectangle(width: 50, height: 42), waterfront: waterfront, elevation: elevation)
    }

    private let river = Waterfront(type: .river, edge: .west, widthM: 10, flowSpeedMps: 0.8, elevationDropM: 1.5)

    @Test func boundsInsetFromTheNamedEdge() {
        #expect(WaterfrontModel.bounds(of: plot(waterfront: river)) == Rect(minX: 0, minY: 0, width: 10, height: 42))

        var edited = river
        edited.edge = .north
        #expect(WaterfrontModel.bounds(of: plot(waterfront: edited)) == Rect(minX: 0, minY: 0, width: 50, height: 10))

        edited.edge = .south
        #expect(WaterfrontModel.bounds(of: plot(waterfront: edited)) == Rect(minX: 0, minY: 32, width: 50, height: 10))

        edited.edge = .east
        #expect(WaterfrontModel.bounds(of: plot(waterfront: edited)) == Rect(minX: 40, minY: 0, width: 10, height: 42))
    }

    @Test func oversizedWidthClampsToThePlotSpan() {
        var edited = river
        edited.widthM = 1000
        #expect(WaterfrontModel.bounds(of: plot(waterfront: edited)) == Rect(minX: 0, minY: 0, width: 50, height: 42))
    }

    @Test func noWaterfrontHasNoBounds() {
        #expect(WaterfrontModel.bounds(of: plot()) == nil)
    }

    @Test func hydroFeasibilityChecksEitherThreshold() {
        #expect(WaterfrontModel.isHydroFeasible(plot(waterfront: river)))
        var weak = river
        weak.flowSpeedMps = 0.1
        weak.elevationDropM = 0.2
        #expect(!WaterfrontModel.isHydroFeasible(plot(waterfront: weak)))
        #expect(!WaterfrontModel.isHydroFeasible(plot()))
    }

    @Test func elevationInterpolatesLinearlyFromTheHighEdge() {
        let sloped = plot(elevation: PlotElevation(highEdge: .north, dropM: 3))
        #expect(ElevationModel.elevation(on: sloped, at: Point(x: 25, y: 0)) == 3)
        #expect(ElevationModel.elevation(on: sloped, at: Point(x: 25, y: 42)) == 0)
        #expect(ElevationModel.elevation(on: sloped, at: Point(x: 25, y: 21)) == 1.5)
    }

    @Test func elevationRespectsEveryHighEdge() {
        #expect(abs(ElevationModel.elevation(on: plot(elevation: PlotElevation(highEdge: .south, dropM: 3)), at: Point(x: 10, y: 10)) - 0.7142857142857142) < 1e-9)
        #expect(abs(ElevationModel.elevation(on: plot(elevation: PlotElevation(highEdge: .east, dropM: 3)), at: Point(x: 10, y: 10)) - 0.6000000000000001) < 1e-9)
        #expect(abs(ElevationModel.elevation(on: plot(elevation: PlotElevation(highEdge: .west, dropM: 3)), at: Point(x: 10, y: 10)) - 2.4000000000000004) < 1e-9)
    }

    @Test func noElevationOrZeroDropIsFlat() {
        #expect(ElevationModel.elevation(on: plot(), at: Point(x: 5, y: 5)) == 0)
        #expect(ElevationModel.elevation(on: plot(elevation: PlotElevation(highEdge: .north, dropM: 0)), at: Point(x: 5, y: 5)) == 0)
    }

    @Test func contourLinesAreEvenlySpacedAtANiceInterval() {
        let sloped = plot(elevation: PlotElevation(highEdge: .north, dropM: 3))
        let lines = ElevationModel.contourLines(on: sloped)
        #expect(lines.count == 5)
        #expect(lines.map(\.elevationM) == [0.5, 1, 1.5, 2, 2.5])
        #expect(lines[0].a == Point(x: 0, y: 35))
        #expect(lines[0].b == Point(x: 50, y: 35))
        #expect(lines[2].a == Point(x: 0, y: 21))
    }

    @Test func flatPlotHasNoContourLines() {
        #expect(ElevationModel.contourLines(on: plot()).isEmpty)
    }
}
