// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-b",
    products: [
        .library(name: "LibB", targets: ["LibB"]),
    ],
    dependencies: [
        .package(workspaceMember: "lib-a"),
    ],
    targets: [
        .target(
            name: "LibB",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
            ],
        ),
    ],
)
