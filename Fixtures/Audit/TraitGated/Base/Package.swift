// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Base",
    products: [
        .library(name: "Base", targets: ["Base"]),
    ],
    targets: [
        .target(name: "Base"),
    ]
)
