// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "upstream",
    products: [
        .library(name: "Upstream", targets: ["Upstream"]),
    ],
    targets: [
        .target(name: "Upstream"),
    ]
)
