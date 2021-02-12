// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Bar",
    products: [
        .library(name: "Bar", targets: ["Bar"]),
    ],
    targets: [
        .target(name: "Bar", path: "./"),
    ]
)
