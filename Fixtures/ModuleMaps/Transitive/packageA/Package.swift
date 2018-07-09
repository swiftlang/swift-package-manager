// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "packageA",
    dependencies: [
        .package(url: "../packageB", from: "1.0.0"),
    ],
    targets: [
        .target(name: "packageA", dependencies: ["packageB"], path: "Sources"),
    ]
)
