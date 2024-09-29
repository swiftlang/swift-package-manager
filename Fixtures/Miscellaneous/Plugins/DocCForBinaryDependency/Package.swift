// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DemoKit",
    products: [
        .library(name: "DemoKit", targets: ["DemoKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .binaryTarget(name: "FooKit", path: "FooKit.xcframework"),
        .target(
            name: "DemoKit",
            dependencies: ["FooKit"]
        ),   
    ]
)
