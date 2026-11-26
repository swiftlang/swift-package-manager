// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeneratedOnlyTargets",
    targets: [
        .target(name: "GeneratedLibrary", plugins: ["Generator"]),
        .executableTarget(name: "GeneratedExecutable", plugins: ["Generator"]),
        .testTarget(name: "GeneratedTests", dependencies: ["GeneratedLibrary"], plugins: ["Generator"]),
        .executableTarget(name: "Runner", dependencies: ["GeneratedLibrary"]),
        .executableTarget(name: "GenerateSources"),
        .plugin(name: "Generator", capability: .buildTool(), dependencies: ["GenerateSources"]),
    ]
)
