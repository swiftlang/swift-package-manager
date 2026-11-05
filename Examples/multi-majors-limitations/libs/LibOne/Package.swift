// swift-tools-version: 5.9
import PackageDescription

// Pinned to Shared 1.x only.
let package = Package(
    name: "LibOne",
    products: [
        .library(name: "LibOne", targets: ["LibOne"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "1.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(
            name: "LibOne",
            dependencies: [.product(name: "Shared", package: "Shared")]
        ),
    ]
)
