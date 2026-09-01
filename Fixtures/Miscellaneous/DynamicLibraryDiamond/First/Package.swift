// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "First",
    products: [
        .library(
            name: "First",
            type: .dynamic,
            targets: ["First"])
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "First",
            dependencies: [
                .product(name: "Shared", package: "Shared")
            ])
    ]
)
