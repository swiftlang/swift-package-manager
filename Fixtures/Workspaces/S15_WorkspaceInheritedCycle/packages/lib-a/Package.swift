// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(workspaceInherited: "lib-x"),
    ],
    targets: [
        .target(
            name: "LibA",
            dependencies: [
                .product(name: "LibX", package: "lib-x"),
            ],
        ),
    ],
)
