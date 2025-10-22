// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "exec",
    dependencies: [
        .package(path: "../secondDyna")
    ],
    targets: [
        .executableTarget(
            name: "exec",
            dependencies: ["secondDyna"]),
        .testTarget(
            name: "DynaTests",
            dependencies: ["exec"])
    ]
)
