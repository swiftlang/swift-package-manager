// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .library(name: "Foo", targets: ["Foo"]),
    ],
    targets: [
        .target(name: "Foo", path: "./"),
    ]
)
