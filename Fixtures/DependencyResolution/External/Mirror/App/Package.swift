// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "../Foo", .branch("main")),
        .package(url: "../Bar", .branch("main")),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Foo", package: "Foo"),
            .product(name: "Bar", package: "Bar"),
        ], path: "./")
    ]
)
