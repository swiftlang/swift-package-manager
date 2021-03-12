// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "ContrivedTestPlugin",
    targets: [
        // A local tool that uses a build tool plugin.
        .executableTarget(
            name: "MyLocalTool",
            dependencies: [
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
            name: "MySourceGenBuildTool"
        ),
    ]
)
