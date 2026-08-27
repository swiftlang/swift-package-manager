// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Second",
    products: [
        .library(
            name: "Second",
            type: .dynamic,
            targets: ["Second"])
    ],
    dependencies: [
        .package(path: "../Shared")
    ],
    targets: [
        .target(
            name: "Second",
            dependencies: [
                .product(name: "Shared", package: "Shared")
            ])
    ]
)
