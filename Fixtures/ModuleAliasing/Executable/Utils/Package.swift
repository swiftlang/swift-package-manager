// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Utils",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils"),
    ]
)
