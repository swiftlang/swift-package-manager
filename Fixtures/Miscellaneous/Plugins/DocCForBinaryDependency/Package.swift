// swift-tools-version: 5.9
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
