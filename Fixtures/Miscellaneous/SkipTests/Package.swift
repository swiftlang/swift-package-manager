// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Example",
    targets: [
        .target(
            name: "Example",
            dependencies: []),
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example"]),
    ]
)
