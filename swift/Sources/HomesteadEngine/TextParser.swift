import Foundation

/// Bounded-vocabulary extraction from the free-text brief, per PRD §9.5: text
/// is matched against a fixed dictionary rather than sent to an open-ended
/// model, so results stay deterministic and explainable. Terms outside the
/// dictionary are surfaced, not silently dropped. Ported from
/// `src/engine/textParser.ts`.
///
/// The term tables are ordered arrays, not dictionaries: `crops`/`animals`/
/// `infrastructure` are first-match-wins over synonyms ("chickens", "hens"
/// and "poultry" all resolve to `poultry`, in the order this file declares
/// them), and Swift's `Dictionary` has no defined iteration order. A plain
/// dictionary here would make match order — and with it every fixture that
/// depends on the merged brief — nondeterministic across runs.
public enum TextParser {
    private static let cropTerms: [(term: String, value: String)] = [
        ("potato", "potato"), ("potatoes", "potato"),
        ("grain", "grain"), ("wheat", "grain"), ("barley", "grain"),
        ("vegetable", "vegetable"), ("vegetables", "vegetable"), ("veggies", "vegetable"),
        ("berry", "berries"), ("berries", "berries"), ("bramble", "berries"),
        ("raspberry", "berries"), ("raspberries", "berries"),
        ("orchard", "orchard"), ("fruit", "orchard"), ("trees", "orchard"),
        ("vineyard", "vineyard"), ("grapes", "vineyard"), ("vines", "vineyard"),
        ("greenhouse", "greenhouse"),
        ("hydroponic", "hydroponic"), ("hydroponics", "hydroponic"),
        ("raised bed", "raised-beds"), ("raised beds", "raised-beds"),
    ]

    private static let animalTerms: [(term: String, value: String)] = [
        ("goat", "goats"), ("goats", "goats"),
        ("chicken", "poultry"), ("chickens", "poultry"), ("hen", "poultry"), ("hens", "poultry"), ("poultry", "poultry"),
    ]

    private static let infraTerms: [(term: String, value: String)] = [
        ("solar", "solar"), ("solar panels", "solar"), ("panels", "solar"),
        ("well", "well"),
        ("septic", "septic"),
        ("generator", "generator"), ("backup power", "generator"),
        ("water tank", "water-tank"), ("tank", "water-tank"),
        ("compost", "compost"),
        ("cellar", "cellar"), ("root cellar", "cellar"),
        ("woodshed", "woodshed"), ("firewood", "woodshed"),
        ("garage", "garage"),
        ("barn", "barn"),
        ("pool", "pool"), ("swimming pool", "pool"),
        ("gazebo", "gazebo"), ("pavilion", "gazebo"),
        ("apiary", "apiary"), ("bees", "apiary"), ("beehives", "apiary"), ("beekeeping", "apiary"),
        ("banya", "banya"), ("sauna", "banya"), ("bathhouse", "banya"),
        ("smokehouse", "smokehouse"), ("smoker", "smokehouse"),
        ("workshop", "workshop"),
        ("cistern", "rainwater-cistern"), ("rainwater tank", "rainwater-cistern"), ("rainwater cistern", "rainwater-cistern"),
        ("dock", "dock"), ("pier", "dock"), ("boat dock", "dock"), ("jetty", "dock"),
        ("micro-hydro", "micro-hydro"), ("micro hydro", "micro-hydro"),
        ("hydro turbine", "micro-hydro"), ("water turbine", "micro-hydro"),
    ]

    private static let styleTerms: [(term: String, delta: Double)] = [
        ("beautiful", 20), ("ornamental", 25), ("decorative", 15), ("elegant", 15),
        ("utilitarian", -25), ("practical", -15), ("functional", -10), ("minimal", -10),
        ("ergonomic", -5), ("compact", -10), ("easy", -5),
    ]

    private static let modeTerms: [(term: String, mode: PlanningMode)] = [
        ("productive", .productionMax), ("production", .productionMax),
        ("maximize", .productionMax), ("maximum", .productionMax),
        ("low maintenance", .minimumMaintenance), ("minimum maintenance", .minimumMaintenance), ("maintenance", .minimumMaintenance),
        ("beautiful", .beautyBalanced), ("balanced", .beautyBalanced), ("beauty", .beautyBalanced),
        ("safe", .safetyFirst), ("safety", .safetyFirst), ("secure", .safetyFirst),
    ]

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "for", "with", "of", "to", "i", "want", "need", "something", "is", "that", "my",
    ]

    private static let householdPattern = try! NSRegularExpression(
        pattern: #"family of (\d+)|(\d+)\s*(?:people|person|adults)"#,
        options: [.caseInsensitive]
    )

    public struct Extraction: Equatable, Sendable {
        public var crops: [String]
        public var animals: [String]
        public var infrastructure: [String]
        public var aestheticDelta: Double
        public var suggestedModes: [PlanningMode]
        public var householdSize: Int?
        public var unrecognizedTerms: [String]
    }

    /// Every term in `dict` whose word-bounded pattern appears in `text`,
    /// deduplicated to first occurrence by declaration order — matching a
    /// JavaScript `Set` built by iterating `Object.entries` in insertion
    /// order, which is exactly what `dict`'s array order preserves here.
    private static func findAll(_ text: String, in dict: [(term: String, value: String)]) -> (matches: [String], consumedTerms: [String]) {
        var seen = Set<String>()
        var matches: [String] = []
        var consumedTerms: [String] = []
        for (term, value) in dict where containsWord(term, in: text) {
            consumedTerms.append(term)
            if seen.insert(value).inserted { matches.append(value) }
        }
        return (matches, consumedTerms)
    }

    private static func containsWord(_ term: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    public static func parse(_ text: String) -> Extraction {
        let lower = text.lowercased()
        let crops = findAll(lower, in: cropTerms)
        let animals = findAll(lower, in: animalTerms)
        let infra = findAll(lower, in: infraTerms)

        var aestheticDelta = 0.0
        var styleConsumed: [String] = []
        for (term, delta) in styleTerms where containsWord(term, in: lower) {
            aestheticDelta += delta
            styleConsumed.append(term)
        }

        var modes: [PlanningMode] = []
        var seenModes = Set<PlanningMode>()
        var modeConsumed: [String] = []
        for (term, mode) in modeTerms where containsWord(term, in: lower) {
            modeConsumed.append(term)
            if seenModes.insert(mode).inserted { modes.append(mode) }
        }

        let householdSize = matchedHouseholdSize(in: lower)

        var consumedTerms: [String] = []
        consumedTerms.append(contentsOf: crops.consumedTerms)
        consumedTerms.append(contentsOf: animals.consumedTerms)
        consumedTerms.append(contentsOf: infra.consumedTerms)
        consumedTerms.append(contentsOf: styleConsumed)
        consumedTerms.append(contentsOf: modeConsumed)
        let consumedText: String = consumedTerms.joined(separator: " ").lowercased()
        let consumedWords: Set<String> = Set(
            consumedText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        )

        // Mirrors `lower.replace(/[^a-z\s]/g, '')`: ascii a-z and whitespace
        // survive, everything else is deleted outright — not blanked to a
        // space, which would keep words apart. A hyphen or apostrophe
        // between two letters instead fuses them: "micro-hydro" becomes
        // "microhydro", "don't" becomes "dont". Only a genuine gap (an
        // existing run of whitespace) still separates words.
        let scrubbed = String(lower.unicodeScalars.filter { scalar in
            (("a" as Unicode.Scalar)...("z" as Unicode.Scalar)).contains(scalar) || CharacterSet.whitespaces.contains(scalar)
        })
        let words = scrubbed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        var seenWords = Set<String>()
        var unrecognizedTerms: [String] = []
        for word in words {
            guard word.count > 3, !consumedWords.contains(word), !stopwords.contains(word) else { continue }
            if seenWords.insert(word).inserted {
                unrecognizedTerms.append(word)
                if unrecognizedTerms.count == 12 { break }
            }
        }

        return Extraction(
            crops: crops.matches,
            animals: animals.matches,
            infrastructure: infra.matches,
            aestheticDelta: aestheticDelta,
            suggestedModes: modes,
            householdSize: householdSize,
            unrecognizedTerms: unrecognizedTerms
        )
    }

    private static func matchedHouseholdSize(in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = householdPattern.firstMatch(in: text, range: range) else { return nil }
        for groupIndex in [1, 2] {
            guard let groupRange = Range(match.range(at: groupIndex), in: text) else { continue }
            return Int(text[groupRange])
        }
        return nil
    }

    /// Merges extracted signals into the structured brief. Free text adds to
    /// structured fields — it never overrides them, per PRD §9.5: a
    /// contradiction should surface, not vanish silently.
    public static func merge(_ base: StructuredInputs, with extraction: Extraction) -> StructuredInputs {
        var merged = base
        // `base || extraction || 1` in the original: JS `||` treats 0 as
        // falsy, so a zero household size or a zero extracted size both fall
        // through rather than sticking.
        if base.householdSize != 0 {
            merged.householdSize = base.householdSize
        } else if let extracted = extraction.householdSize, extracted != 0 {
            merged.householdSize = extracted
        } else {
            merged.householdSize = 1
        }
        merged.crops = orderedUnion(base.crops, extraction.crops)
        if !extraction.animals.isEmpty, base.animals.isEmpty {
            merged.animals = extraction.animals.map { AnimalRequest(type: $0, count: $0 == "goats" ? 4 : 6) }
        }
        merged.infrastructure = orderedUnion(base.infrastructure, extraction.infrastructure)
        merged.aestheticPreference = min(100, max(0, base.aestheticPreference + extraction.aestheticDelta))
        return merged
    }

    private static func orderedUnion(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in a + b where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
