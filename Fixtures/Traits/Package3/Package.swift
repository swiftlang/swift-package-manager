// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Package3",
    products: [
        .library(
            name: "Package3Library1",
            targets: ["Package3Library1"]
        ),
    ],
    traits: [
        .default(enabledTraits: ["Package3Trait3"]),
        .trait(name: "Package3Trait1", enabledTraits: ["Package3Trait2"]),
        .trait(name: "Package3Trait2", enabledTraits: ["Package3Trait3"]),
        "Package3Trait3",
    ],
    targets: [
        .target(
            name: "Package3Library1"
        ),
    ]
)
