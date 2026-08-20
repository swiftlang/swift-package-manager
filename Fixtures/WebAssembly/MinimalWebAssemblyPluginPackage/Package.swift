// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalWebAssemblyPluginPackage",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: "PluginToolHelpers"),
    ],
    targets: [
        .target(name: "PluginToolSupport"),
        .executableTarget(name: "GenerateTool", dependencies: [
            "PluginToolSupport",
            .product(name: "PluginToolHelpers", package: "PluginToolHelpers"),
        ]),
        .plugin(
            name: "GenerateSourcePlugin",
            capability: .buildTool(),
            dependencies: ["GenerateTool"]
        ),
        .target(name: "PluginConsumer", plugins: ["GenerateSourcePlugin"]),
        .executableTarget(name: "PluginClient", dependencies: ["PluginConsumer"]),
        .testTarget(name: "MinimalWebAssemblyPluginPackageTests", dependencies: ["PluginConsumer"]),
    ],
    swiftLanguageModes: [.v5]
)
