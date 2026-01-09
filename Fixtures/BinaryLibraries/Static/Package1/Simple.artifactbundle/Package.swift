// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Simple",
    products: [
        .library(name: "Simple", type: .static, targets: ["Simple"]),
    ],
    targets: [
        .target(
            name: "Simple",
            path: "."
        ),
    ]
)
