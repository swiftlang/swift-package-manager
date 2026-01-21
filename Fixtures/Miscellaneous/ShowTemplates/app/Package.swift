// swift-tools-version:6.3.0
import PackageDescription

let package = Package(
    name: "GenerateFromTemplate",
    products: [
        .executable(
            name: "dealer",
            targets: ["dealer"]
        ),
    ] + .template(name: "GenerateFromTemplate"),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
    ],
    targets: [
        .executableTarget(
            name: "dealer",
        ),
    ] + .template(
        name: "GenerateFromTemplate",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system"),
        ],
        initialPackageType: .executable,
        templatePermissions: [
            .allowNetworkConnections(scope: .local(ports: [1200]), reason: ""),
        ],
        description: "A template that generates a starter executable package"
    )
)
