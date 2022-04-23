// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "PluginGeneratedResources",
    targets: [
        .executableTarget(name: "PluginGeneratedResources", plugins: ["Generator"]),
        .plugin(name: "Generator", capability: .buildTool()),
    ]
)
