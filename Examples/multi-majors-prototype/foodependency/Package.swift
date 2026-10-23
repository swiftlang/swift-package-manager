// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "foodependency",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Foo",
            targets: ["FooModule"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "4.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FooModule",
            dependencies: [
                .product(
                    name: "Alamofire",
                    package: "Alamofire"
                )
            ],
            path: "Sources/foodependency",
        ),
        .testTarget(
            name: "foodependencyTests",
            dependencies: ["FooModule"]
        ),
    ]
)
