// swift-tools-version: 999.0
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
            dependencies: [
                .product(name: "MySourceGenBuildToolPlugin", package: "MySourceGenPlugin")
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
