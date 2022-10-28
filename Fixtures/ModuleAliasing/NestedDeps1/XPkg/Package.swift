// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XPkg",
    products: [
        .library(name: "X", targets: ["X"]),
    ],
    dependencies: [
        .package(path: "../YPkg"),
    ],
    targets: [
        .target(name: "X",
                dependencies: [
                    "Utils",
                    .product(name: "Utils",
                             package: "YPkg",
                             moduleAliases: ["Utils": "FooUtils"]
                            ),
                ]),
        .target(name: "Utils", dependencies: [])
    ]
)
