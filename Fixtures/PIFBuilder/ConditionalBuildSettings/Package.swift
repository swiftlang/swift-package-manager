// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ConditionalBuildSettings",
    products: [
        .library(
            name: "ConditionalBuildSettings",
            type: .dynamic,
            targets: ["ConditionalBuildSettings"]
        ),
    ],
    targets: [
        .target(
            name: "ConditionalBuildSettings",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug)),
            ]
        ),
    ]
)
