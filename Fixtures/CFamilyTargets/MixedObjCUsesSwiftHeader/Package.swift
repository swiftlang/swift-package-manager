// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "MixedObjCUsesSwiftHeader",
    targets: [
        .target(name: "MixedLib"),
        .executableTarget(name: "Runner", dependencies: ["MixedLib"]),
    ]
)
