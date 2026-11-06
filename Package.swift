// swift-tools-version: 6.0
import PackageDescription

// macOS is listed only so `swift test` can run the Foundation-only core on a
// Mac. The SDK is an iOS product; host apps on macOS are not supported.
let package = Package(
    name: "Identified",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Identified", targets: ["Identified"]),
    ],
    targets: [
        .target(name: "IdentifiedCore"),
        .target(name: "Identified", dependencies: ["IdentifiedCore"], resources: [.process("Resources")]),
        // Stubs and fixtures shared by both test targets. Not in any product.
        .target(name: "IdentifiedTestSupport", dependencies: ["IdentifiedCore"], path: "Tests/Support"),
        .testTarget(name: "IdentifiedCoreTests", dependencies: ["IdentifiedCore", "IdentifiedTestSupport"]),
        .testTarget(name: "IdentifiedTests", dependencies: ["Identified", "IdentifiedCore", "IdentifiedTestSupport"]),
    ]
)
