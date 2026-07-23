// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "MixedClangSuperclassSwiftSubclass",
    targets: [
        .target(name: "MixedLib"),
        .target(name: "Consumer", dependencies: ["MixedLib"]),
    ]
)
