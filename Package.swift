// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "warplink-ios-sdk",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WarpLink",
            targets: ["WarpLink"]
        )
    ],
    targets: [
        .target(
            name: "WarpLink",
            path: "Sources/WarpLink"
        ),
        .testTarget(
            name: "WarpLinkTests",
            dependencies: ["WarpLink"],
            path: "Tests/WarpLinkTests"
        )
    ]
)
