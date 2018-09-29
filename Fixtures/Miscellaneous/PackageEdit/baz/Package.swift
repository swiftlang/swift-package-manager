// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "baz",
    products: [
        .library(name: "baz", targets: ["baz"]),
    ],
    targets: [
        .target(name: "baz", path: "Sources"),
    ]
)
