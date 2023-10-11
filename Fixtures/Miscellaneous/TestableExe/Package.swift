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
        .executableTarget(
            name: "TestableAsyncExe1"
        ),
        .executableTarget(
            name: "TestableAsyncExe2"
        ),
        .executableTarget(
            name: "TestableAsyncExe3"
        ),
        .executableTarget(
            name: "TestableAsyncExe4"
        ),
        .testTarget(
            name: "TestableAsyncExeTests",
            dependencies: [
                "TestableAsyncExe1",
                "TestableAsyncExe2",
                "TestableAsyncExe3",
                "TestableAsyncExe4",
            ]
        ),
    ]
)
