// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "libb",
    products: [
        .library(name: "LibB", targets: ["LibB"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/SharedC", "2.0.0"..<"3.0.0"),
    ],
    targets: [
        .target(name: "LibB", dependencies: [.product(name: "SharedC", package: "SharedC")]),
    ]
)
