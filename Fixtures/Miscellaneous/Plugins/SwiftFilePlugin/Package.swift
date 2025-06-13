// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftFilePluginFixture",
    products: [
        .library(
            name: "SwiftFilePluginFixture",
            targets: ["SwiftFilePluginFixture"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftFilePluginFixture",
            plugins: [
                .plugin(name: "MyCustomBuildTool")
            ]
        ),
        .plugin(
            name: "MyCustomBuildTool",
            capability: .buildTool()
        )
    ]
)
