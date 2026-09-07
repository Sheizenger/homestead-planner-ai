import Foundation

/// The scale bar and north arrow are screen-space furniture, drawn by the
/// view directly (per `Viewport`'s doc comment) so they stay put at any zoom
/// — but *how long* the scale bar should read is a real calculation, not a
/// drawing concern, so it lives here where it can be tested without a Mac.
public enum ScaleBar {
    /// A round number of metres (1/2/5 × a power of ten) whose on-screen
    /// length at the current `metresPerPoint` lands close to
    /// `targetScreenLength`, without exceeding `maxScreenLength` — the web
    /// app's scale bar was fixed at "10 m," which reads fine at one zoom
    /// level and either vanishes or overruns the canvas at another.
    public static func niceLength(metresPerPoint: Double, targetScreenLength: Double = 80, maxScreenLength: Double = 160) -> Double {
        guard metresPerPoint > 0 else { return 1 }
        let rawMetres = targetScreenLength * metresPerPoint
        var metres = niceNumber(rawMetres)
        // niceNumber only ever rounds to the *nearest* 1/2/5, which can
        // land on the step above the target and overrun maxScreenLength at
        // a coarse zoom; step down through the sequence until it fits.
        while metres / metresPerPoint > maxScreenLength, metres > 0 {
            metres = stepDown(metres)
        }
        return metres
    }

    private static func niceNumber(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized < 1.5 ? 1 : normalized < 3.5 ? 2 : normalized < 7.5 ? 5 : 10
        return nice * magnitude
    }

    private static func stepDown(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        let normalized = (value / magnitude).rounded()
        if normalized > 5 { return 5 * magnitude }
        if normalized > 2 { return 2 * magnitude }
        if normalized > 1 { return 1 * magnitude }
        return 5 * (magnitude / 10)
    }
}
