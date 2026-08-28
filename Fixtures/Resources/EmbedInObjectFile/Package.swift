// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "EmbedInObjectFile",
    targets: [
        .target(
            name: "EmbeddedResourceLibrary",
            resources: [
                .embedInCode("best.txt", representation: .objectFile),
                .embedInCode("empty.bin", representation: .objectFile),
            ]
        ),
        .executableTarget(
            name: "EmbedInObjectFile",
            dependencies: ["EmbeddedResourceLibrary"]
        ),
    ]
)
