// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyBinaryTargetExePlugin",

    products: [
        .executable(
            name: "MyPluginExe",
            targets: ["MyPluginExe"]
        ),
        .plugin(
            name: "MyPlugin",
            targets: ["MyPlugin"]
        ),
        .executable(
            name: "MyBinaryTargetExe",
            targets: ["MyBinaryTargetExeArtifactBundle"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MyPluginExe",
            dependencies: [],
            exclude: [],
        ),

        .plugin(
            name: "MyPlugin",
            capability: .buildTool(),
            dependencies: ["MyPluginExe", "MyBinaryTargetExeArtifactBundle"]
        ),
        .binaryTarget(
            name: "MyBinaryTargetExeArtifactBundle",
            path: "Dependency/MyBinaryTargetExeArtifactBundle.artifactbundle"
        ),
    ]
)
