// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DoNotFilterLinkerDiagnostics",
    targets: [
        .executableTarget(
            name: "DoNotFilterLinkerDiagnostics",
            linkerSettings: [
                .linkedLibrary("z"),
                .unsafeFlags(["-lz"]),
                // should produce: ld: warning: ignoring duplicate libraries: '-lz'
            ]
        ),
    ]
)
