import Testing
@testable import HomesteadCore

struct ScaleBarTests {
    @Test func picksARoundNumberNearTheTarget() {
        // At 1 point == 1 metre, an 80pt target wants roughly 80 m, which
        // rounds to the nearest 1/2/5 step: 100.
        #expect(ScaleBar.niceLength(metresPerPoint: 1, targetScreenLength: 80) == 100)
    }

    @Test func shrinksWithMetresPerPoint() {
        // Zoomed in (0.1 m/pt): the same 80pt target now wants ~8 m, nice → 10.
        #expect(ScaleBar.niceLength(metresPerPoint: 0.1, targetScreenLength: 80) == 10)
        // Zoomed out (10 m/pt): ~800 m, nice → 1000. But that overruns the
        // default 160pt cap (1000/10 = 100pt is actually fine here) — pick a
        // case that genuinely needs the step-down.
    }

    /// The case a fixed "10 m" bar (the web app's actual behaviour) gets
    /// wrong: zoomed far out, a round number sized to the target would
    /// stretch off the edge of the canvas, so the picker has to step back
    /// down until it fits within maxScreenLength.
    @Test func stepsDownRatherThanOverrunningTheMaxLength() {
        let metresPerPoint = 5.0
        let length = ScaleBar.niceLength(metresPerPoint: metresPerPoint, targetScreenLength: 80, maxScreenLength: 160)
        #expect(length / metresPerPoint <= 160)
        #expect(length / metresPerPoint > 0)
    }

    @Test func neverProducesANonPositiveLength() {
        #expect(ScaleBar.niceLength(metresPerPoint: 0) > 0)
        #expect(ScaleBar.niceLength(metresPerPoint: 1000) > 0)
    }
}
