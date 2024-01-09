// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CommandPluginDiagnostics",
    targets: [
        .plugin(
            name: "diagnostics-stub",
            capability: .command(intent: .custom(
                verb: "print-diagnostics",
                description: "Writes diagnostic messages for testing"
            ))
        ),
        .executableTarget(
            name: "placeholder"
        ),
    ]
)
