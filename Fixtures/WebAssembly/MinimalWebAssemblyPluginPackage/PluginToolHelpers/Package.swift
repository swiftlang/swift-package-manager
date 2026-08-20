// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PluginToolHelpers",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "PluginToolHelpers", targets: ["PluginToolHelpers"]),
    ],
    targets: [
        .target(name: "PluginToolHelpers"),
    ],
    swiftLanguageModes: [.v5]
)
