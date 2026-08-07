// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "BuildToolPluginCrash",
    targets: [
        .target(
            name: "Client",
            plugins: [
                "CrashingPlugin",
            ]
        ),
        .plugin(
            name: "CrashingPlugin",
            capability: .buildTool()
        ),
    ]
)
