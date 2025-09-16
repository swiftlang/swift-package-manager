// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PluginGeneratedResources",
    targets: [
        .executableTarget(name: "PluginGeneratedResources", plugins: ["Generator"]),
        .plugin(name: "Generator", capability: .buildTool()),
    ]
)
