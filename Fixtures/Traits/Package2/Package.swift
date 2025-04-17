// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Package2",
    products: [
        .library(
            name: "Package2Library1",
            targets: ["Package2Library1"]
        ),
    ],
    traits: [
        Trait(name: "Package2Trait1", enabledTraits: ["Package2Trait2"]),
        "Package2Trait2",
    ],
    targets: [
        .target(
            name: "Package2Library1"
        ),
    ]
)
