// swift-tools-version: 6.2

import PackageDescription

// Compile-only proof that an existing `onLink` caller still builds in the two
// ways an app can be set up: Swift 5 mode, and Swift 6 with every declaration
// main-actor isolated by default (`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`).
// Run `./check.sh`.
let package = Package(
    name: "OnLinkIsolation",
    platforms: [.iOS(.v15), .macOS(.v11)],
    dependencies: [.package(name: "warplink-ios-sdk", path: "../..")],
    targets: [
        .target(
            name: "Swift5Mode",
            dependencies: [.product(name: "WarpLink", package: "warplink-ios-sdk")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "Swift6MainActorDefault",
            dependencies: [.product(name: "WarpLink", package: "warplink-ios-sdk")],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
    ]
)
