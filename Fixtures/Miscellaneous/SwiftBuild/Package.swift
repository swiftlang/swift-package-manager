// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "TestableExe",
    targets: [
        .executableTarget(
            name: "Test",
            path: "."
        ),
    ]
)
