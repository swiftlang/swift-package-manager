// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedLibraryTestTarget",
    targets: [
        .target(name: "MixedCore"),
        .testTarget(name: "MixedCoreTests", dependencies: ["MixedCore"]),
    ]
)
