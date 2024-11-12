// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenReplay",
    platforms: [
            .iOS(.v13)
        ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "OpenReplay",
            targets: ["OpenReplay"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "4.0.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", .upToNextMajor(from: "4.8.5")),
    ],
    targets: [
        .target(
            name: "OpenReplay",
            dependencies: [
                .product(name: "SWCompression", package: "SWCompression"),
                .product(name: "DeviceKit", package: "DeviceKit"),
            ]
        ),
        .testTarget(
            name: "ORTrackerTests",
            dependencies: ["OpenReplay"]
        ),
    ]
)
