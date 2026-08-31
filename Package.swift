// swift-tools-version: 6.2
import PackageDescription

// Glasshouse is deliberately split so that everything worth testing builds and
// runs on macOS. `swift test` is the development loop; the simulator is a gate.
let package = Package(
    name: "Glasshouse",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "GlasshouseCore", targets: ["GlasshouseCore"]),
        .library(name: "GlasshouseSensors", targets: ["GlasshouseSensors"]),
    ],
    targets: [
        // Pure Swift. No CoreMotion, CoreLocation, HealthKit, or any other
        // Apple sensor framework may be imported here — see docs/architecture.md.
        .target(name: "GlasshouseCore"),

        // Live adapters over Apple frameworks, guarded by #if os(iOS).
        // Kept as thin as possible because it cannot be unit tested on macOS.
        .target(name: "GlasshouseSensors", dependencies: ["GlasshouseCore"]),

        .testTarget(name: "GlasshouseCoreTests", dependencies: ["GlasshouseCore"]),
    ]
)
