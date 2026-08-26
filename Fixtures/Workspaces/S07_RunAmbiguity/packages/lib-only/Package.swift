// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-only",
    products: [
        .library(name: "LibOnly", targets: ["LibOnly"]),
    ],
    targets: [
        .target(name: "LibOnly"),
    ],
)
