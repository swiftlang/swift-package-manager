// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "TestableExe",
    products: [
        .executable(name: "testable-exe", targets: ["TestableExe"])
    ],
    targets: [
        .executableTarget(
            name: "TestableExe"
        ),
        .testTarget(
            name: "TestableExeTests",
            dependencies: [
                "TestableExe",
            ]
        ),
    ]
)
