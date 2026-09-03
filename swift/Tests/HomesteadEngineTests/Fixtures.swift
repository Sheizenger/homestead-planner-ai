import Foundation

/// Locates the repo's `fixtures/` directory relative to this source file, so
/// the golden fixtures load identically under `swift test` and under Xcode
/// without SPM copying 700 KB of JSON into every test bundle.
enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // HomesteadEngineTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("fixtures")

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try JSONDecoder().decode(type, from: data)
    }
}
