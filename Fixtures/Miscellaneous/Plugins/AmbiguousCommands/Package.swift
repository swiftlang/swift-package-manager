// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AmbiguousCommands",
    dependencies: [
        .package(path: "Dependencies/A"),
        .package(path: "Dependencies/B"),
    ],
    targets: [
        .executableTarget(
            name: "AmbiguousCommands"),
    ]
)
