// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-b",
    products: [
        .library(name: "LibB", targets: ["LibB"]),
        .library(name: "LibBExtra", targets: ["LibBExtra"]),
    ],
    targets: [
        .target(name: "LibB"),
        .target(name: "LibBExtra"),
    ],
)
