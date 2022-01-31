// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "ContrivedTestPlugin",
    targets: [
        // A local tool that uses a build tool plugin.
        .executableTarget(
            name: "MyLocalTool",
            plugins: [
                "MySourceGenBuildToolPlugin",
                "MyAmbiguouslyNamedCommandPlugin",
            ]
        ),
        // The plugin that generates build tool commands to invoke MySourceGenBuildTool.
        .plugin(
            name: "MySourceGenBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                "MySourceGenBuildTool",
            ]
        ),
        // The command line tool that generates source files.
        .executableTarget(
            name: "MySourceGenBuildTool"
        ),
        // Plugin that emits commands with a generic name.
        .plugin(
            name: "MyAmbiguouslyNamedCommandPlugin",
            capability: .buildTool(),
            dependencies: [
                "MySourceGenBuildTool",
            ]
        ),
        // Sample system library target for testing.
        .systemLibrary(
            name: "libpcre",
            path: "Sources/libpcre",
            pkgConfig: "libpcre",
            providers: [
                .apt(["libpcre-dev"])
            ]
        )
    ]
)
