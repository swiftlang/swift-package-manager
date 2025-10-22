// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "secondDyna",
    products: [
        .library(
            name: "secondDyna",
            type: .dynamic,
            targets: ["secondDyna"])
    ],
    dependencies: [
        .package(path: "../firstDyna")
    ],
    targets: [
        .target(
            name: "secondDyna",
            dependencies: ["firstDyna"])
    ]
)
