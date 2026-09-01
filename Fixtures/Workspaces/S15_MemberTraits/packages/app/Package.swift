// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(
            workspaceMember: "lib-a",
            traits: [
                "core",
                "extras",
            ],
        ),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
            ],
        ),
    ],
)
