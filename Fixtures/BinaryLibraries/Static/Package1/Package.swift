// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Package1",
    targets: [
        .executableTarget(
            name: "Example",
            dependencies: [
                "Simple",
                "Wrapper"
            ]
        ),
        .target(
            name: "Wrapper",
            dependencies: [
                "Simple"
            ]
        ),
        .binaryTarget(
            name: "Simple",
            path: "Simple.artifactbundle"
        ),
    ]
)
