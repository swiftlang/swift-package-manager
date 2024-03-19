// swift-tools-version: 5.11

import PackageDescription

let package = Package(
    name: "DoNotFilterLinkerDiagnostics",
    targets: [
        .executableTarget(
            name: "DoNotFilterLinkerDiagnostics",
            linkerSettings: [
                .unsafeFlags(["-Lfoobar"]),
            ]
        ),
    ]
)
