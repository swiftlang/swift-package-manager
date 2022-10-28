// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Apkg",
    products: [
        .executable(name: "AApp", targets: ["AApp"]),
        .library(name: "Utils", type: .dynamic, targets: ["Utils"]),
    ],
    targets: [
        .executableTarget(name: "AApp", dependencies: ["Utils"]),
        .target(name: "Utils", dependencies: [])
    ]
)
