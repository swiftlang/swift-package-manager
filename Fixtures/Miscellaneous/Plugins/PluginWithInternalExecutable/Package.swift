// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "PluginWithInternalExecutable",
    products: [
        .plugin(
            name: "PluginScriptProduct",
            targets: ["PluginScriptTarget"]
        ),
    ],
    targets: [
        .plugin(
            name: "PluginScriptTarget",
            capability: .buildTool(),
            dependencies: [
                "PluginExecutable",
            ]
        ),
        .executableTarget(
            name: "PluginExecutable"
        ),
    ]
)
