// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Simple",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "Simple",
            targets: ["Simple"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-play-experimental", branch: "main"),
    ],
    targets: [
        .target(
            name: "Simple",
            dependencies: [
                .product(name: "Playgrounds", package: "swift-play-experimental"),
            ]
        ),
    ]
)
