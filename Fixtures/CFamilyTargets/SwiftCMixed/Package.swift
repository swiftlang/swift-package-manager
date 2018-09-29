// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SwiftCMixed",
    targets: [
        .target(name: "SeaExec", dependencies: ["SeaLib"]),
        .target(name: "CExec", dependencies: ["SeaLib"]),
        .target(name: "SeaLib", dependencies: []),
    ]
)
