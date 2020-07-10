// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "packageC",
    products: [
        .library(name: "packageC", targets: ["x"]),
    ],
    dependencies: [
        .package(url: "../packageD", from: "1.0.0"),
    ],
    targets: [
        .target(name: "x", dependencies: ["CFoo"]),
    ]
)
