// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "dep2",
    products: [
        .library(name: "dep2", targets: ["dep2"])
    ],
    targets: [
        .target(name: "dep2", path: "./")
    ]
)
