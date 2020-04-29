// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "double-free",
    targets: [
        .target(
            name: "lib",
            dependencies: []),
        .target(
            name: "exec",
            dependencies: ["lib"]),
        .testTarget(
            name: "libTests",
            dependencies: ["lib"]),
    ]
)
