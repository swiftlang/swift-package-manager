// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Root",
    traits: [
        .trait(name: "Extra"),
    ],
    dependencies: [
        .package(url: "../Base", from: "1.0.0"),
        .package(url: "../Gated", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Root",
            dependencies: [
                .product(name: "Base", package: "Base"),
                .product(name: "Gated", package: "Gated", condition: .when(traits: ["Extra"])),
            ]
        ),
    ]
)
