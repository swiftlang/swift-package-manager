// swift-tools-version:4.2
import PackageDescription
let package = Package(
    name: "tool",
    dependencies: [
        .package(path: "Dependency"),
    ],
    targets: [
        .target(
            name: "tool",
            dependencies: ["DynamicLibrary"]),
    ]
)
