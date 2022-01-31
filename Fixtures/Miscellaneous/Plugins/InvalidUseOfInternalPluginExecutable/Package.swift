// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "InvalidUseOfInternalPluginExecutable",
    dependencies: [
        .package(path: "../PluginWithInternalExecutable")
    ],
    targets: [
        .executableTarget(
            name: "RootTarget",
            dependencies: [
                .product(name: "PluginExecutable", package: "PluginWithInternalExecutable")
            ],
            plugins: [
                .plugin(name: "PluginScriptProduct", package: "PluginWithInternalExecutable")
            ]
        ),
    ]
)
