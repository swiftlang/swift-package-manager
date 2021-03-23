// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(name: "Foo", url: "../Foo", .branch("main")),
        .package(name: "Bar", url: "../Bar", .branch("main")),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Foo", package: "Foo"),
            .product(name: "Bar", package: "Bar"),
        ], path: "./src")
    ]
)
