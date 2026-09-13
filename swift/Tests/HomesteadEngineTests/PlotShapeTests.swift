import Testing
@testable import HomesteadEngine

/// `describe` is the inverse of `lShape`/`rectangle`, and it exists because a
/// document stores only the boundary polygon: the plot editor has to recover
/// "L-shaped, north-west, 20 × 15" from six points, or reopening a saved plan
/// squares off an L-shaped plot the moment its width is nudged.
struct PlotShapeTests {
    @Test func aRectangleIsRecognisedAsOne() {
        #expect(PlotShape.describe(PlotShape.rectangle(width: 60, height: 45)) == .rectangle)
    }

    /// Round-tripping every corner, because each of the four `lShape` cases
    /// lays its vertices out differently and only one of them was ever the
    /// one anybody looked at.
    @Test func everyLShapeRoundTripsThroughDescribe() {
        for corner in PlotCorner.allCases {
            let boundary = PlotShape.lShape(width: 60, height: 45, notchWidth: 20, notchHeight: 15, corner: corner)
            #expect(
                PlotShape.describe(boundary) == .lShape(notchWidth: 20, notchHeight: 15, corner: corner),
                Comment(rawValue: corner.rawValue)
            )
        }
    }

    /// `lShape` clamps its notch to keep the polygon valid, so what comes back
    /// is the clamped notch — the geometry that exists — not what was asked for.
    @Test func describeReportsTheClampedNotchNotTheRequestedOne() {
        let boundary = PlotShape.lShape(width: 60, height: 45, notchWidth: 900, notchHeight: 0, corner: .se)
        #expect(PlotShape.describe(boundary) == .lShape(notchWidth: 59, notchHeight: 1, corner: .se))
    }

    /// Anything this type didn't build is left alone rather than rounded to
    /// the nearest shape the editor knows how to draw.
    @Test func otherPolygonsAreFreeform() {
        #expect(PlotShape.describe([]) == .freeform)
        #expect(PlotShape.describe([Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 5, y: 8)]) == .freeform)
        // A degenerate "plot" with no area has no corners to tell apart.
        #expect(PlotShape.describe(PlotShape.rectangle(width: 0, height: 40)) == .freeform)
    }
}
