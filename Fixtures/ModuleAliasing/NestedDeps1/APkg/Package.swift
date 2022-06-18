// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "APkg",
    products: [
        .library(name: "A", targets: ["A"]),
    ],
    dependencies: [
        .package(path: "../BPkg"),
        .package(path: "../CPkg"),
    ],
    targets: [
        .target(name: "A",
                dependencies: [
                    .product(name: "Utils",
                             package: "BPkg",
                             moduleAliases: ["Utils": "FooUtils"]
                            ),
                    .product(name: "Utils",
                             package: "CPkg",
                             moduleAliases: ["Utils": "CarUtils"]
                            ),
                ]),
    ]
)
