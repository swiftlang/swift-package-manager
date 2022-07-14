// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "MissingPlugin",
    targets: [
        .target(name: "MissingPlugin", plugins: ["NonExistingPlugin"]),
    ]
)
