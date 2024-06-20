// swift-tools-version: 999.0.0

@_spi(ExperimentalTraits) import PackageDescription

let package = Package(
    name: "Package4",
    products: [
        .library(
            name: "Package4Library1",
            targets: ["Package4Library1"]
        ),
    ],
    traits: [
        Trait(name: "Package4Trait1", isDefault: true),
    ],
    targets: [
        .target(
            name: "Package4Library1"
        ),
    ]
)
