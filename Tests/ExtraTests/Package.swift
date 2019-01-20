// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "ExtraTests",
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .testTarget(
            name: "ExtraTests",
            dependencies: ["SPMUtility"]),
    ]
)
