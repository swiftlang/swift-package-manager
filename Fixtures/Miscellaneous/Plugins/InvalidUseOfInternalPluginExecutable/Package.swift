// swift-tools-version: 5.5
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
