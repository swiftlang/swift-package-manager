// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "SandboxTesterPlugin",
    targets: [
        // A local tool that uses a build tool plugin.
        .executableTarget(
            name: "MyLocalTool",
            plugins: [
                "MySourceGenBuildToolPlugin",
            ]
        ),
        // The plugin that tries to write outside the sandbox.
        .plugin(
            name: "MySourceGenBuildToolPlugin",
            capability: .buildTool()
        ),
    ]
)
