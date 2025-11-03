// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "ExistentialAnyMigration",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .target(name: "Library", plugins: [.plugin(name: "Plugin")]),
        .plugin(name: "Plugin", capability: .buildTool, dependencies: ["Tool"]),
        .executableTarget(name: "Tool"),
    ]
)
