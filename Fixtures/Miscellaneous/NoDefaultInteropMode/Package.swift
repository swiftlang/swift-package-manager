// swift-tools-version: 6.3
// ^^^ important: must be < 6.4

import PackageDescription

let package = Package(
    name: "NoDefaultInteropMode",
    targets: [
        .testTarget(name: "NoDefaultInteropModeTests"),
    ]
)
