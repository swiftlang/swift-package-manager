// swift-tools-version: 999.0

import PackageDescription

let package = Package(
    name: "ExternalLib",
    products: [
        .library(name: "DebugTool", targets: ["DebugTool"]),
        .library(name: "ReleaseTool", targets: ["ReleaseTool"]),
    ],
    targets: [
        .target(name: "DebugTool"),
        .target(name: "ReleaseTool"),
    ]
)
