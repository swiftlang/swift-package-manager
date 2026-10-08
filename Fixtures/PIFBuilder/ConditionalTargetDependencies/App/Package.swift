// swift-tools-version: 999.0

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../ExternalLib"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .target(name: "Always"),
                .target(name: "DebugOnly", condition: .when(configuration: .debug)),
                .product(name: "DebugTool", package: "ExternalLib", condition: .when(configuration: .debug)),
                .product(name: "ReleaseTool", package: "ExternalLib", condition: .when(configuration: .release)),
            ]
        ),
        .target(name: "Always"),
        .target(name: "DebugOnly"),
    ]
)
