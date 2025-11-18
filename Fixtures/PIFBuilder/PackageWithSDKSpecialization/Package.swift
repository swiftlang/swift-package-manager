// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PackageWithSDKSpecialization",
    platforms: [ .macOS("10.15.foo") ],
    products: [
        .library(
            name: "PackageWithSDKSpecialization",
            targets: ["PackageWithSDKSpecialization"]),
    ],
    targets: [
        .target(
            name: "PackageWithSDKSpecialization",
            dependencies: []
        ),
        .target(
            name: "Executable",
            dependencies: ["PackageWithSDKSpecialization"]
        ),
    ]
)
