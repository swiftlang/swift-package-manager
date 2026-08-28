// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(workspaceInherited: "other-lib"),
    ],
    targets: [
        .target(
            name: "LibA",
            dependencies: [
                .product(name: "OtherLib", package: "other-lib"),
            ],
        ),
    ],
)
