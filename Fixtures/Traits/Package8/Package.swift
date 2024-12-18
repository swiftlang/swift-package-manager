// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Package8",
    products: [
        .library(
            name: "Package8Library1",
            targets: ["Package8Library1"]
        ),
    ],
    traits: [
        "Package8Trait1"
    ],
    targets: [
        .target(
            name: "Package8Library1"
        ),
    ]
)
