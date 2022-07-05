// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MyBuildToolPluginDependencies",
    targets: [
        // A local tool that uses a build tool plugin.
        .executableTarget(
            name: "MyLocalTool",
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
        // A command line tool that generates source files.
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
    ]
)
