// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PartiallyUnusedDependency",
    products: [
        .executable(
            name: "MyExecutable",
            targets: ["MyExecutable"]
        ),
    ],
    dependencies: [
        .package(path: "Dep")
    ],
    targets: [
        .executableTarget(
            name: "MyExecutable",
            dependencies: [.product(name: "MyDynamicLibrary", package: "Dep")]
        ),
        .plugin(
            name: "dump-artifacts-plugin",
            capability: .command(
                intent: .custom(verb: "dump-artifacts-plugin", description: "Dump Artifacts"),
                permissions: []
            )
        )
    ]
)
