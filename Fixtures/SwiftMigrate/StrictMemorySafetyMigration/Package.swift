// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "StrictMemorySafetyMigration",
    targets: [
        .target(name: "Diagnostics", path: "Sources", exclude: ["Fixed"]),
    ]
)
