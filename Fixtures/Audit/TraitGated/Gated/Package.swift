// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gated",
    products: [
        .library(name: "Gated", targets: ["Gated"]),
    ],
    targets: [
        .target(name: "Gated"),
    ]
)
