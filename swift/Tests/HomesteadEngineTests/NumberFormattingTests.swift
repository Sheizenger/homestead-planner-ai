import Testing
@testable import HomesteadEngine

/// Every case here is a real `.toLocaleString()`/`.toFixed(1)` value
/// captured from Node, tie cases included.
struct NumberFormattingTests {
    @Test func groupingMatchesToLocaleString() {
        let cases: [(Int, String)] = [
            (0, "0"), (5, "5"), (100, "100"), (999, "999"),
            (1000, "1,000"), (1500, "1,500"), (2000, "2,000"),
            (12345, "12,345"), (-1200, "-1,200"), (1000000, "1,000,000"), (250, "250"),
        ]
        for (input, expected) in cases {
            #expect(NumberFormatting.usGrouped(input) == expected, Comment(rawValue: "\(input)"))
        }
    }

    /// The tie cases are the point: `1.45` and `-1.25` are where a
    /// scaled-Double or shortest-round-trip-string approach disagrees with
    /// JavaScript, because the double's exact value sits a hair off the
    /// decimal boundary its shortest string representation shows.
    @Test func toFixedOneMatchesJavaScriptIncludingTies() {
        let cases: [(Double, String)] = [
            (0.0, "0.0"), (1.5, "1.5"), (1.45, "1.4"), (1.05, "1.1"),
            (0.05, "0.1"), (2.449999999, "2.4"), (-1.25, "-1.3"),
            (-1.35, "-1.4"), (3.15, "3.1"),
        ]
        for (input, expected) in cases {
            #expect(NumberFormatting.toFixed(input, 1) == expected, Comment(rawValue: "\(input)"))
        }
    }
}
