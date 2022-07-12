// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "PluginOnly",
    products: [
        .plugin(name: "MyPlugin", targets: ["MyPlugin"]),
    ],
    targets: [
        .plugin(name: "MyPlugin", capability: .buildTool()),
    ]
)
