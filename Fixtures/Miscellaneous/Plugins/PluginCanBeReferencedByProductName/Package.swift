// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "PluginCanBeReferencedByProductName",
    products: [
        .plugin(name: "MyPluginProduct", targets: ["MyPlugin"]),
    ],
    targets: [
        .target(name: "PluginCanBeReferencedByProductName", plugins: ["MyPluginProduct"]),
        .executableTarget(name: "Exec"),
        .plugin(name: "MyPlugin", capability: .buildTool(), dependencies: ["Exec"]),
    ]
)
