// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "EmbedInObjectFileWithoutLifetimes",
    targets: [
        .executableTarget(
            name: "EmbedInObjectFileWithoutLifetimes",
            resources: [
                .embedInCode("payload.txt", representation: .objectFile),
            ]
        ),
    ]
)
