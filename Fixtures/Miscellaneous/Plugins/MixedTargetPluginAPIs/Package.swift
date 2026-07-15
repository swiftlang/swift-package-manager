// swift-tools-version: 999.0;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedTargetPluginAPIs",
    targets: [
        .target(name: "SwiftOnly"),
        .target(name: "ClangOnly"),
        .target(
            name: "Mixed",
            cSettings: [.define("PREPROCESSOR_MACRO"), .headerSearchPath("extra_headers")],
            swiftSettings: [.define("SWIFT_DEFINITION")]
        ),
        .plugin(
            name: "DumpTargets",
            capability: .command(
                intent: .custom(verb: "dump-targets", description: "Dumps target metadata via the PackagePlugin API")
            )
        ),
    ]
)
