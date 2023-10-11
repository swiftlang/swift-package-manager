// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "TestableExe",
    targets: [
        .executableTarget(
            name: "TestableExe1"
        ),
        .executableTarget(
            name: "TestableExe2"
        ),
        .executableTarget(
            name: "TestableExe3"
        ),
        .testTarget(
            name: "TestableExeTests",
            dependencies: [
                "TestableExe1",
                "TestableExe2",
                "TestableExe3",
            ]
        ),
    ]
)
