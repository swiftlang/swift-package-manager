// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "packageB",
    products: [
        .library(name: "packageB", targets: ["y"]),
    ],
    dependencies: [
        .package(url: "../packageC", from: "1.0.0"),
    ],
    targets: [
        .target(name: "y", dependencies: ["packageC"]),
    ]
)
