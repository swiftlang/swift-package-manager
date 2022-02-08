// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MySourceGenClient",
    dependencies: [
        .package(path: "../MySourceGenPlugin")
    ],
    targets: [
        // A tool that uses a plugin.
        .executableTarget(
            name: "MyTool",
            plugins: [
                .plugin(name: "MySourceGenBuildToolPlugin", package: "MySourceGenPlugin")
            ]
        ),
        // A unit test that uses the plugin.
        .testTarget(
            name: "MyTests",
            plugins: [
                .plugin(name: "MySourceGenBuildToolPlugin", package: "MySourceGenPlugin")
            ]
        )
    ]
)
