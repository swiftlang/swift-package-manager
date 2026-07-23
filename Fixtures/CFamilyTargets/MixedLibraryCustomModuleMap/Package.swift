// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedLibraryCustomModuleMap",
    targets: [
        .target(name: "MixedCore"),
        .executableTarget(name: "Client", dependencies: ["MixedCore"]),
    ]
)
