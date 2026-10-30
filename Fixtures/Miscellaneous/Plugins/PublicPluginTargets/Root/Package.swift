// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "Root",
    dependencies: [
        .package(path: "../Dep"),
    ],
    targets: [
        .target(
            name: "Root",
            dependencies: [
                .target(name: "DepLib", package: "Dep"),
            ]
        ),
    ]
)
