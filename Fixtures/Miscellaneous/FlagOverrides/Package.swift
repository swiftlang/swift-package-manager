// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlagOverrides",
    targets: [
        .executableTarget(
            name: "FlagOverrides",
            plugins: [
                "GenerateSourcePlugin",
            ]
        ),
        .plugin(
            name: "GenerateSourcePlugin",
            capability: .buildTool(),
            dependencies: [
                "GenerateTool",
            ]
        ),
        .executableTarget(
            name: "GenerateTool"
        ),
        .plugin(
            name: "BuildAndRunPlugin",
            capability: .command(
                intent: .custom(verb: "build-and-run", description: "Build and run the executable")
            )
        ),
    ]
)
