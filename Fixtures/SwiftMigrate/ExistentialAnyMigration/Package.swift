// swift-tools-version:5.8

import PackageDescription

let package = Package(
    name: "ExistentialAnyMigration",
    targets: [
        .target(name: "Diagnostics", path: "Sources", exclude: ["Fixed"]),
    ]
)
