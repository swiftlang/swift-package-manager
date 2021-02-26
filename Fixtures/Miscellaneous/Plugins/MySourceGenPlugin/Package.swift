// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "MySourceGenPlugin",
    products: [
        // The product that vends MySourceGenPlugin to client packages.
        .plugin(
            name: "MySourceGenPlugin",
            targets: ["MySourceGenPlugin"]
        ),
        .executable(
            name: "MySourceGenTool",
            targets: ["MySourceGenTool"]
        )
    ],
    targets: [
        // A local tool that uses a plugin.
        .executableTarget(
            name: "MyLocalTool",
            dependencies: [
                "MySourceGenPlugin",
            ]
        ),
        // The target that implements the plugin and generates commands to invoke MySourceGenTool.
        .plugin(
            name: "MySourceGenPlugin",
            capability: .buildTool(),
            dependencies: [
                "MySourceGenTool"
            ]
        ),
        // The command line tool that generates source files.
        .executableTarget(
            name: "MySourceGenTool",
            dependencies: [
                "MySourceGenToolLib",
            ]
        ),
        // A library used by MySourceGenTool (not the client).
        .target(
            name: "MySourceGenToolLib"
        ),
        // A runtime library that the client needs to link against.
        .target(
            name: "MySourceGenRuntimeLib"
        ),
        // Unit tests for the plugin.
        .testTarget(
            name: "MySourceGenPluginTests",
            dependencies: [
                "MySourceGenRuntimeLib"
            ],
            plugins: [
                "MySourceGenPlugin"
            ]
        )
    ]
)
