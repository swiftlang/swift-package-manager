// swift-tools-version: 5.9
import PackageDescription

// Pinned to Shared 3.x only.
let package = Package(
    name: "LibThree",
    products: [
        .library(name: "LibThree", targets: ["LibThree"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "3.0.0"..<"4.0.0"),
    ],
    targets: [
        .target(
            name: "LibThree",
            dependencies: [.product(name: "Shared", package: "Shared")]
        ),
    ]
)
