// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "Dependency",
    products: [
        .library(name: "Automatic", targets: ["Automatic"]),
        .library(name: "Dynamic", type: .dynamic, targets: ["Dynamic"])
    ],
    targets: [
        .target(name: "Automatic"),
        .target(name: "Dynamic")
    ]
)
