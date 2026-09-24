// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CoreDependency",
    products: [
        .library(name: "CoreDependencyV2", targets: ["CoreDependencyV2"]),
        .library(name: "CoreDependencyV3", targets: ["CoreDependencyV3"]),
    ],
    targets: [
        .target(name: "Common"),
        .target(name: "CoreDependencyV2", dependencies: ["Common"]),
        .target(name: "CoreDependencyV3", dependencies: ["Common"]),
    ]
)
