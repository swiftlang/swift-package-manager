// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "MySourceGenExtension",
    products: [
        // The product that vends MySourceGenExt to client packages.
        // .extension(
        //     name: "MySourceGenExt",
        //     target: "MySourceGenExt"
        // )
    ],
    targets: [
        // A local tool that uses an extension.
        .executableTarget(
            name: "MyLocalTool",
            dependencies: [
                "MySourceGenExt",
                "MySourceGenTool"
            ]
        ),
        // The target that implements the extension and generates commands to invoke MySourceGenTool.
        .extension(
            name: "MySourceGenExt",
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
        // Unit tests for the extension.
        .testTarget(
            name: "MySourceGenExtTests",
            dependencies: [
                "MySourceGenExt",
                "MySourceGenRuntimeLib"
            ]
        )
    ]
)
