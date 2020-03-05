// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ParseableInterfaces",
    products: [
    ],
    targets: [
        .target(name: "A", dependencies: []),
        .target(name: "B", dependencies: ["A"]),
    ])
