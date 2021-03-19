// swift-tools-version: 999.0
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
