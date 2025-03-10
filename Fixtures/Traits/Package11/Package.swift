// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Package11",
    products: [
        .library(
            name: "Package11Library1",
            targets: ["Package11Library1"]
        ),
    ],
    targets: [
        .target(
            name: "Package11Library1"
        ),
    ]
)
