// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bardependency",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Bar",
            targets: ["BarModule"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BarModule",
            dependencies: [
                .product(
                    name: "Alamofire",
                    package: "Alamofire"
                )
            ],
            path: "Sources/bardependency"
        ),
        .testTarget(
            name: "bardependencyTests",
            dependencies: ["BarModule"]
        ),
    ]
)
