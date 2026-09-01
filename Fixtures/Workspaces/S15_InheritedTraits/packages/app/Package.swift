// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(
            workspaceInherited: "traited-lib",
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
                .product(name: "TraitedLib", package: "traited-lib"),
            ],
        ),
    ],
)
