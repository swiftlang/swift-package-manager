// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "TestableAsyncExe",
    platforms: [
        .macOS(.v10_15),
    ],
    targets: [
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
