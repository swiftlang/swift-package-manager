// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedExecutableTestTarget",
    targets: [
        .executableTarget(name: "MixedTool"),
        .testTarget(name: "MixedToolTests", dependencies: ["MixedTool"]),
    ]
)
