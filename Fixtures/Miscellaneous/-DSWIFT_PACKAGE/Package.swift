// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "ExtraCommandLineFlags",
    targets: [
        .target(name: "CLib"),
        .target(name: "SwiftExec", dependencies: ["CLib"]),
    ]
)
