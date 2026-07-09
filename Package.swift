// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MacSvnDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacSvnCore",
            targets: ["MacSvnCore"]
        )
    ],
    targets: [
        .target(
            name: "MacSvnCore"
        ),
        .testTarget(
            name: "MacSvnCoreTests",
            dependencies: ["MacSvnCore"]
        )
    ]
)
