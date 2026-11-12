// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Local",
    products: [
        .library(name: "Local", targets: ["Local"]),
    ],
    targets: [
        .target(name: "Local"),
    ]
)
