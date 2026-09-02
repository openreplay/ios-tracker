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
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.5.0"),
        // Capped below 4.9.0 on purpose: SWCompression raised its minimum to iOS 17
        // there, so an open 4.x range makes every consumer targeting iOS 13-16 fail
        // to resolve. Package.resolved pins 4.8.6 for this repo, but consumers of a
        // library ignore that file, so the bound has to live here.
        .package(url: "https://github.com/tsolomko/SWCompression.git", "4.8.5"..<"4.9.0"),
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
