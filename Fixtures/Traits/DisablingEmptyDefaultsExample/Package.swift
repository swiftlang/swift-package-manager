// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DisablingEmptyDefaultsExample",
    dependencies: [
        .package(
            path: "../Package11",
            traits: []
        ),
    ],
    targets: [
        .executableTarget(
            name: "DisablingEmptyDefaultsExample"
        ),
    ]
)
