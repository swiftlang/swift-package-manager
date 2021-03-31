// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "TestableExe",
    targets: [
        .target(
            name: "TestableExe1"
        ),
        .target(
            name: "TestableExe2"
        ),
        .target(
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
