// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestableExe",
    targets: [
        .executableTarget(
            name: "TestableExe",
            resources: [.embedInCode("foo.txt")]
        ),
        .testTarget(
            name: "TestableExeTests",
            dependencies: [
                "TestableExe",
            ]
        ),
    ]
)
