// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-b",
    products: [
        .library(name: "LibB", targets: ["LibB"]),
    ],
    targets: [
        .target(name: "LibB"),
        .testTarget(name: "LibBTests", dependencies: ["LibB"]),
        .testTarget(name: "LibBXCTests", dependencies: ["LibB"]),
    ],
)
