// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ExecutableAndLibrary",
    products: [
        .executable(
            name: "FooExecutable",
            targets: ["FooExecutable"]
        ),
        .library(
            name: "FooLibrary",
            targets: ["FooLibrary"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FooExecutable",
            dependencies: ["FooLibrary"]
        ),
        .target(
            name: "FooLibrary"
        )
    ],
    swiftLanguageModes: [.v6]
)
