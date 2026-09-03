import Foundation

/// Warning text embeds two pieces of JavaScript's default number formatting.
/// Both are ports, not approximations — the shapes below are verified
/// against real Node output in `NumberFormattingTests`, including the tie
/// cases where a naive port disagrees with JavaScript.
public enum NumberFormatting {
    /// `Number.prototype.toLocaleString()`'s default (en-US) grouping: a
    /// comma every three digits, no decimals for the whole numbers this
    /// engine ever formats (household sizes, areas already rounded to
    /// metres).
    public static func usGrouped(_ value: Int) -> String {
        let negative = value < 0
        var digits = Array(String(abs(value)))
        var i = digits.count - 3
        while i > 0 {
            digits.insert(",", at: i)
            i -= 3
        }
        return (negative ? "-" : "") + String(digits)
    }

    /// `Number.prototype.toFixed(decimals)`: round-half-away-from-zero
    /// against the double's *exact* value, not its shortest round-trip
    /// decimal string. `1.45` prints as `"1.45"` in both languages (that
    /// really is the shortest decimal that round-trips to this double), but
    /// the double's true value is a hair under 1.45, so `.toFixed(1)` gives
    /// `"1.4"` — rounding the displayed string, or a scaled-then-rounded
    /// Double (`(v * 10).rounded() / 10`, which reintroduces its own binary
    /// rounding before the intended one), both get this wrong. A
    /// high-precision decimal expansion resolves the tie the same way
    /// JavaScript does.
    public static func toFixed(_ value: Double, _ decimals: Int) -> String {
        let negative = value < 0 || (value == 0 && value.sign == .minus)
        let magnitude = abs(value)
        let precise = String(format: "%.30f", magnitude)
        let parts = precise.split(separator: ".", maxSplits: 1)
        var intPart = Array(parts[0])
        var fracPart = Array(parts.count > 1 ? parts[1] : Substring())
        while fracPart.count <= decimals { fracPart.append("0") }

        let roundDigit = fracPart[decimals]
        fracPart = Array(fracPart[0..<decimals])

        if roundDigit >= "5" {
            var i = fracPart.count - 1
            var carry = true
            while carry, i >= 0 {
                if fracPart[i] == "9" {
                    fracPart[i] = "0"
                } else {
                    fracPart[i] = Character(UnicodeScalar(fracPart[i].asciiValue! + 1))
                    carry = false
                }
                i -= 1
            }
            if carry {
                var j = intPart.count - 1
                while carry, j >= 0 {
                    if intPart[j] == "9" {
                        intPart[j] = "0"
                    } else {
                        intPart[j] = Character(UnicodeScalar(intPart[j].asciiValue! + 1))
                        carry = false
                    }
                    j -= 1
                }
                if carry { intPart.insert("1", at: 0) }
            }
        }

        var result = (negative ? "-" : "") + String(intPart)
        if decimals > 0 { result += "." + String(fracPart) }
        return result
    }
}
