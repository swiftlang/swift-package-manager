// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "firstDyna",
    products: [
        .library(
            name: "firstDyna",
            type: .dynamic,
            targets: ["firstDyna"])
    ],
    targets: [
        .target(
            name: "firstDyna",
            dependencies: ["Core"]),
        .target(
            name: "Core",
            dependencies: [])
    ]
)
