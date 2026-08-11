// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CommandPluginTestProductArtifacts",
    products: [
        .library(
            name: "MyLibrary",
            type: .static,
            targets: ["MyLibrary"]
        ),
    ],
    targets: [
        .target(
            name: "MyLibrary"
        ),
        .testTarget(
            name: "FirstTests",
            dependencies: ["MyLibrary"]
        ),
        .testTarget(
            name: "SecondTests",
            dependencies: ["MyLibrary"]
        ),
        .plugin(
            name: "dump-artifacts-plugin",
            capability: .command(
                intent: .custom(verb: "dump-artifacts-plugin", description: "Dump Artifacts"),
                permissions: []
            )
        ),
    ]
)
