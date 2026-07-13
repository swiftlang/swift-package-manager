// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedLanguageClient",
    targets: [
        .target(name: "MixedCore"),
        .executableTarget(name: "Client", dependencies: ["MixedCore"]),
    ]
)
