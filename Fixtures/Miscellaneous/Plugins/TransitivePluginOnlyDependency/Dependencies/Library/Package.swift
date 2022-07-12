// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Library",
    products: [
        .library(name: "Library", targets: ["Library"]),
    ],
    dependencies: [
        .package(path: "../PluginOnly")
    ],
    targets: [
        .target(name: "Library", plugins: [.plugin(name: "MyPlugin", package: "PluginOnly")]),
    ]
)
