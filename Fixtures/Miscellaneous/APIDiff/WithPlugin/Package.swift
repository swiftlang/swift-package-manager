// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "package-with-plugin",
    products: [.library(name: "PackageLib", targets: ["TargetLib"])],
    targets: [
        .target(name: "TargetLib"),
        .executableTarget(name: "BuildTool", dependencies: ["TargetLib"]),
        .plugin(
            name: "BuildPlugin",
            capability: .command(intent: .custom(verb: "do-it-now", description: "")),
            dependencies: ["BuildTool"]
        ),
    ]
)
