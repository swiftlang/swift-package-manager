// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "ExistentialAnyMigration",
    targets: [
        .target(name: "Library", dependencies: ["CommonLibrary"], plugins: [.plugin(name: "Plugin")]),
        .plugin(name: "Plugin", capability: .buildTool, dependencies: ["Tool"]),
        .executableTarget(name: "Tool", dependencies: ["CommonLibrary"]),
        .target(name: "CommonLibrary"),
    ]
)
