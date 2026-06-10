// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClientOfPluginWithInternalExecutable",
    dependencies: [
        .package(path: "../PluginWithInternalExecutable")
    ],
    targets: [
        .executableTarget(
            name: "RootTarget",
            plugins: [
                .plugin(name: "PluginScriptProduct", package: "PluginWithInternalExecutable")
            ]
        ),
    ]
)
