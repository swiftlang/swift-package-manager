// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "Root",
    dependencies: [
        .package(path: "../Dependency")
    ],
    targets: [
        .target(
            name: "Target",
            dependencies: [
                .product(name: "Automatic", package: "Dependency")
            ]
        )
    ]
)
