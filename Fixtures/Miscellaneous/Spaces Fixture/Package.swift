// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Spaces Fixture",
    targets: [
        .target(
            name: "Module Name 2",
            dependencies: ["Module Name 1"]),
        .target(
            name: "Module Name 1",
            dependencies: []),
    ]
)
