// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftAndCTargets",
    targets: [
        .target(name: "cLib"),
        .executableTarget(name: "exe", dependencies: ["cLib", "swiftLib"]),
        .target(name: "swiftLib"),
    ]
)
