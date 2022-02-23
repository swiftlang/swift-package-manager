// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyPlugin",
    products: [
        .plugin(
            name: "MyPlugin",
            targets: ["MyPlugin"]
        ),
    ],
    dependencies: [
        .package(path: "../RemoteTool"),
    ],
    targets: [
        .plugin(
            name: "MyPlugin",
            capability: .command(
                intent: .custom(
                    verb: "my-plugin",
                    description: "Tester plugin"
                )
            ),
            dependencies: [
                .product(name: "RemoteTool", package: "RemoteTool"),
                "LocalTool",
                "ImpliedLocalTool",
            ]
        ),
        .executableTarget(
            name: "LocalTool",
            dependencies: ["LocalToolHelperLibrary"],
            path: "Tools/LocalTool"
        ),
        .executableTarget(
            name: "ImpliedLocalTool",
            dependencies: ["LocalToolHelperLibrary"],
            path: "Tools/ImpliedLocalTool"
        ),
        .target(
            name: "LocalToolHelperLibrary",
            path: "Libraries/LocalToolHelperLibrary"
        ),
    ]
)
