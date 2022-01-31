// swift-tools-version: 5.6
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
