// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FooLib1",
    products: [
        .library(name: "FooLib1", targets: ["FooLib1"]),
        .executable(name: "cli", targets: ["cli"]),
    ],
    targets: [
        .target(name: "FooLib1"),
        .target(name: "cli", dependencies: ["FooLib1"]),
    ]
)
