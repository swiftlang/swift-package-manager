// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    targets: [
        .target(name: "LibA"),
        .testTarget(name: "LibATests", dependencies: ["LibA"]),
        .testTarget(name: "LibAXCTests", dependencies: ["LibA"]),
    ],
)
