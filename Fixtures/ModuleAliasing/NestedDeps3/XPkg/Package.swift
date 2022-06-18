// swift-tools-version:5.7
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
                    .product(name: "UtilsInY",
                             package: "YPkg",
                             moduleAliases: ["Utils": "FooUtils"]
                            ),
                ]),
        .target(name: "Utils", dependencies: [])
    ]
)
