// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "MixedExecutableTestTarget",
    targets: [
        .executableTarget(name: "MixedTool"),
        .testTarget(name: "MixedToolTests", dependencies: ["MixedTool"]),
    ]
)
