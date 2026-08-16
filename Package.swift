// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HeartbeatMusic",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "HeartbeatCore", targets: ["HeartbeatCore"])
    ],
    targets: [
        .target(name: "HeartbeatCore"),
        .testTarget(
            name: "HeartbeatCoreTests",
            dependencies: ["HeartbeatCore"]
        )
    ]
)
