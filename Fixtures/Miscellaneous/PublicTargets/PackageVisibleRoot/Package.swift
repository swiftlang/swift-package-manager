// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "PackageVisibleRoot",
    dependencies: [
        .package(path: "../Dep"),
    ],
    targets: [
        .executableTarget(
            name: "Tool",
            dependencies: [
                .target(name: "PackageOnly", package: "Dep"),
            ]
        ),
    ]
)
