// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "ExtraCommandLineFlags",
    targets: [
        .target(name: "CLib"),
        .target(name: "SwiftExec", dependencies: ["CLib"]),
    ]
)
