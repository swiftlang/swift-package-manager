// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "InferIsolatedConformancesMigration",
    targets: [
        .target(name: "Diagnostics", path: "Sources", exclude: ["Fixed"]),
    ]
)
