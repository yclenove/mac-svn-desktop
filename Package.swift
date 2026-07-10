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
        ),
        .library(
            name: "MacSvnApp",
            targets: ["MacSvnApp"]
        ),
        .executable(
            name: "MacSvnDesktopApp",
            targets: ["MacSvnDesktopApp"]
        )
    ],
    targets: [
        .target(
            name: "MacSvnCore"
        ),
        .target(
            name: "MacSvnApp",
            dependencies: ["MacSvnCore"]
        ),
        .executableTarget(
            name: "MacSvnDesktopApp",
            dependencies: ["MacSvnApp"]
        ),
        .testTarget(
            name: "MacSvnCoreTests",
            dependencies: ["MacSvnCore"]
        ),
        .testTarget(
            name: "MacSvnAppTests",
            dependencies: ["MacSvnApp"]
        )
    ]
)
