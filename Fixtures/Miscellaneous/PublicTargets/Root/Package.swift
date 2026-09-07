// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "Root",
    dependencies: [
        .package(path: "../Dep"),
    ],
    targets: [
        .executableTarget(
            name: "Tool",
            dependencies: [
                .target(name: "PublicLib", package: "Dep"),
                .target(name: "PublicPlain", package: "Dep"),
            ]
        ),
    ]
)
