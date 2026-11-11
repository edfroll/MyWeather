// swift-tools-version: 6.2
import PackageDescription

// Approachable Concurrency and import visibility, shared by every target (A-38).
let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

// Pure algorithms: nonisolated by default (A-38).
let coreSettings: [SwiftSetting] = commonSettings + [.defaultIsolation(nil)]

// SwiftUI layer: main actor by default (A-38).
let uiSettings: [SwiftSetting] = commonSettings + [.defaultIsolation(MainActor.self)]

var products: [Product] = [
    .library(name: "ChartKitCore", targets: ["ChartKitCore"]),
]

var targets: [Target] = [
    .target(name: "ChartKitCore", swiftSettings: coreSettings),
    .testTarget(name: "ChartKitCoreTests", dependencies: ["ChartKitCore"], swiftSettings: coreSettings),
]

// ChartKit needs SwiftUI and Charts. The manifest is evaluated on the host, so on Linux
// the package contains only ChartKitCore and its tests (A-41).
#if canImport(SwiftUI)
products.append(.library(name: "ChartKit", targets: ["ChartKit"]))
targets.append(.target(name: "ChartKit", dependencies: ["ChartKitCore"], swiftSettings: uiSettings))
#endif

let package = Package(
    name: "ChartKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
