// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .library(name: "Baz", targets: ["Baz"]),
    ],
    dependencies: [
        .package(path: "./Inner")
    ],
    targets: [
        .target(name: "Baz", dependencies: [.product(name: "InnerBar", package: "Inner")], path: "./Baz")
    ]
)
