// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Sample",
    products: [
        .library(
            name: "Sample",
            targets: [
                "Sample"
            ]
        ),
    ],
    targets: [
        .target(
            name: "Sample"
        ),
    ]
)
