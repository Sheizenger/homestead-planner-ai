// swift-tools-version: 6.0
import PackageDescription

// Two layers of the three described in AGENTS.md. The third — the SwiftUI
// views — lives in the Xcode app target, which depends on this package.
// Nothing here imports SwiftUI, which is what lets the whole package build
// and test on Linux, with no Mac in the loop.
let package = Package(
    name: "Homestead",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HomesteadEngine", targets: ["HomesteadEngine"]),
        .library(name: "HomesteadCore", targets: ["HomesteadCore"]),
    ],
    targets: [
        .target(name: "HomesteadEngine"),
        .target(name: "HomesteadCore", dependencies: ["HomesteadEngine"]),
        .testTarget(name: "HomesteadEngineTests", dependencies: ["HomesteadEngine"]),
        .testTarget(name: "HomesteadCoreTests", dependencies: ["HomesteadCore"]),
    ]
)
