// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "liba",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/SharedC", "1.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(name: "LibA", dependencies: [.product(name: "SharedC", package: "SharedC")]),
    ]
)
