// swift-tools-version: 6.0

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
