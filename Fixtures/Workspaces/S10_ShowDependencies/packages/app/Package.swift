// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(workspaceMember: "lib-a"),
        .package(workspaceInherited: "some-lib"),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
                .product(name: "SomeLib", package: "some-lib"),
            ],
        ),
    ],
)
