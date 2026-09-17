// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "TargetVisibilityPluginAPIs",
    targets: [
        .target(name: "Plain"),
        .libraryTarget(name: "DynamicLib", type: .dynamic, visibility: .public),
        .libraryTarget(name: "Aggregate", dependencies: ["Plain"], visibility: .public),
        .plugin(
            name: "DumpTargets",
            capability: .command(
                intent: .custom(verb: "dump-targets", description: "Dumps target metadata via the PackagePlugin API")
            )
        ),
    ]
)
