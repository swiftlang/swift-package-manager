// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "FooKit",
    products: [
        .library(name: "FooKit", type: .dynamic, targets: ["FooKit"]),
    ],
    targets: [
        .target(name: "FooKit"),
    ]
)
