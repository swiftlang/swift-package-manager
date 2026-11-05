// swift-tools-version: 5.9
import PackageDescription

// Pinned to Shared 2.x only.
let package = Package(
    name: "LibTwo",
    products: [
        .library(name: "LibTwo", targets: ["LibTwo"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "2.0.0"..<"3.0.0"),
    ],
    targets: [
        .target(
            name: "LibTwo",
            dependencies: [.product(name: "Shared", package: "Shared")]
        ),
    ]
)
