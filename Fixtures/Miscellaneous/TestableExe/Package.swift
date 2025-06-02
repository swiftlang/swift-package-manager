// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "TestableExe",
    targets: [
        .executableTarget(
            name: "TestableExe1",
            linkerSettings: [
                .linkedLibrary("swiftCore", .when(platforms: [.windows])), // for swift_addNewDSOImage
            ]
        ),
        .executableTarget(
            name: "TestableExe2",
            linkerSettings: [
                .linkedLibrary("swiftCore", .when(platforms: [.windows])), // for swift_addNewDSOImage
            ]

        ),
        .executableTarget(
            name: "TestableExe3",
            linkerSettings: [
                .linkedLibrary("swiftCore", .when(platforms: [.windows])), // for swift_addNewDSOImage
            ]
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
