// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Exec",
    dependencies: [
        .package(path: "../First"),
        .package(path: "../Second"),
    ],
    targets: [
        .executableTarget(
            name: "Exec",
            dependencies: [
                .product(name: "First", package: "First"),
                .product(name: "Second", package: "Second"),
            ])
    ]
)
