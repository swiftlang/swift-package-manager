// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(workspaceMember: "lib-b"),
    ],
    targets: [
        .target(
            name: "LibA",
            dependencies: [
                .product(name: "LibB", package: "lib-b"),
            ],
        ),
    ],
)
