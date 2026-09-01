// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(
            workspaceInherited: "traited-lib",
            traits: [
                "core",
                "perf",
            ],
        ),
    ],
    targets: [
        .target(
            name: "LibA",
            dependencies: [
                .product(name: "TraitedLib", package: "traited-lib"),
            ],
        ),
    ],
)
