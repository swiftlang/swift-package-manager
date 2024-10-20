// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .library(name: "Foo", targets: ["Foo", "Bar", "Baz"]),
    ],
    dependencies: [
        .package(path: "./Inner")
    ],
    targets: [
        .target(name: "Foo", path: "./Foo"),
        .binaryTarget(name: "Bar", path: "./Bar.xcframework"),
        .target(name: "Baz", dependencies: [.product(name: "InnerBar", package: "Inner")], path: "./Baz")
    ]
)
