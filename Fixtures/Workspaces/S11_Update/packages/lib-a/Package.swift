// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(url: "../../external/other-lib", from: "1.0.0"),
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
