// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "gamePkg",
    products: [
        .library(name: "Game", targets: ["Game"]),
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Game", dependencies: ["Utils"]),
        .target(name: "Utils", dependencies: []),
    ]
)
