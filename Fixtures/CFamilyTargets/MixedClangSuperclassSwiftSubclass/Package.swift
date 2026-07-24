// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "MixedClangSuperclassSwiftSubclass",
    targets: [
        .target(name: "MixedLib"),
        .target(name: "Consumer", dependencies: ["MixedLib"]),
    ]
)
