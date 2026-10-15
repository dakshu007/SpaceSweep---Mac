// swift-tools-version:5.9
import PackageDescription

// SpaceSweep is split into:
//  • SpaceSweepCore — rules, path safety, scanning, planning and cleanup.
//    Pure Foundation so the safety engine can be tested headless.
//  • SpaceSweep     — the native SwiftUI/AppKit macOS app (macOS only).
var products: [Product] = [
    .library(name: "SpaceSweepCore", targets: ["SpaceSweepCore"]),
]

var targets: [Target] = [
    .target(name: "SpaceSweepCore"),
    .testTarget(name: "SpaceSweepCoreTests", dependencies: ["SpaceSweepCore"]),
]

#if os(macOS)
products.append(.executable(name: "SpaceSweep", targets: ["SpaceSweep"]))
targets.append(.executableTarget(name: "SpaceSweep", dependencies: ["SpaceSweepCore"]))
#endif

let package = Package(
    name: "SpaceSweep",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
