// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(workspaceInherited: "some-lib"),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "SomeLib", package: "some-lib"),
            ],
        ),
    ],
)
