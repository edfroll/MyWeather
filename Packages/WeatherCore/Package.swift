// swift-tools-version: 6.2
import PackageDescription

// Data layer: nonisolated by default, Approachable Concurrency (A-38).
let settings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .defaultIsolation(nil),
]

let package = Package(
    name: "WeatherCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WeatherCore", targets: ["WeatherCore"]),
    ],
    targets: [
        .target(name: "WeatherCore", swiftSettings: settings),
        .testTarget(name: "WeatherCoreTests", dependencies: ["WeatherCore"], resources: [.copy("Fixtures")], swiftSettings: settings),
    ],
    swiftLanguageModes: [.v6]
)
