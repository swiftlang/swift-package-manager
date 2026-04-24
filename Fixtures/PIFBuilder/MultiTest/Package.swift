// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MultiTest",
    products: [
        .library(
            name: "MultiTest",
            targets: ["MultiTest"]
        ),
    ],
    targets: [
        .target(
            name: "MultiTest"
        ),
        .testTarget(
            name: "FooTests",
            dependencies: ["MultiTest"]
        ),
        .testTarget(
            name: "BarTests",
            dependencies: ["MultiTest"]
        ),
    ]
)
