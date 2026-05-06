// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommandPluginBuildingBuildToolPlugin",
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"]),
    ],
    targets: [
        .target(
            name: "MyLibrary",
            plugins: [
                "SourceGenPlugin",
            ]
        ),
        .plugin(
            name: "SourceGenPlugin",
            capability: .buildTool(),
            dependencies: [
                "SourceGenTool",
            ]
        ),
        .executableTarget(
            name: "SourceGenTool"
        ),
        .plugin(
            name: "BuildInReleasePlugin",
            capability: .command(
                intent: .custom(verb: "build-release", description: "Build the package in release mode")
            )
        ),
    ]
)
