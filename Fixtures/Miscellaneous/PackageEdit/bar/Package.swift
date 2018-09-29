// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "bar",
    products: [
        .library(name: "bar", targets: ["bar"]),
    ],
    targets: [
        .target(name: "bar", path: "Sources"),
    ]
)
