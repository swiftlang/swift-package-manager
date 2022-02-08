// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "GamePkg",
    products: [
        .library(name: "Game", targets: ["Game"]),
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Game", dependencies: ["Utils"]),
        .target(name: "Utils", dependencies: []),
    ]
)
