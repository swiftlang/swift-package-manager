// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "TransitivePluginOnlyDependency",
    dependencies: [
        .package(path: "Dependencies/Library"),
    ],
    targets: [
        .target(name: "TransitivePluginOnlyDependency", dependencies: ["Library"]),
    ]
)
