// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MySourceGenPluginNoPreBuildCommands",
    products: [
        // The product that vends MySourceGenBuildToolPlugin to client packages.
        .plugin(
            name: "MySourceGenBuildToolPlugin",
            targets: ["MySourceGenBuildToolPlugin"]
        ),
        // The product that vends the MySourceGenBuildTool executable to client packages.
        .executable(
            name: "MySourceGenBuildTool",
            targets: ["MySourceGenBuildTool"]
        ),
    ],
    targets: [
        // A local tool that uses a build tool plugin.
        .executableTarget(
            name: "MyLocalTool",
            plugins: [
                "MySourceGenBuildToolPlugin",
            ]
        ),
        // A local tool that uses a prebuild plugin.
        .executableTarget(
            name: "MyOtherLocalTool",
            plugins: [
                "MySourceGenBuildToolPlugin",
            ]
        ),
        // The plugin that generates build tool commands to invoke MySourceGenBuildTool.
        .plugin(
            name: "MySourceGenBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                "MySourceGenBuildTool",
            ]
        ),
        // The command line tool that generates source files.
        .executableTarget(
            name: "MySourceGenBuildTool",
            dependencies: [
                "MySourceGenBuildToolLib",
            ]
        ),
        // A library used by MySourceGenBuildTool (not the client).
        .target(
            name: "MySourceGenBuildToolLib"
        ),
        // A runtime library that the client needs to link against.
        .target(
            name: "MySourceGenRuntimeLib"
        ),
        // Unit tests for the plugin.
        .testTarget(
            name: "MySourceGenPluginTests",
            dependencies: [
                "MySourceGenRuntimeLib",
            ],
            plugins: [
                "MySourceGenBuildToolPlugin",
            ]
        )
    ]
)
