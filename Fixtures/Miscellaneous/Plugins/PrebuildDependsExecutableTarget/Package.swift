// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "PrebuildDependsExecutableTarget",
    platforms: [ .macOS(.v13) ],
    dependencies: [
    ],
    targets: [
        .executableTarget(name: "MyExecutable"),

        .plugin(
            name: "MyPlugin",
            capability: .buildTool(),
            dependencies: [
                "MyExecutable"
            ]
        ),

        .executableTarget(
            name: "MyClient",
            plugins: [
                "MyPlugin",
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
