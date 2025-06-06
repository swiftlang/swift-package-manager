// swift-tools-version:999.0.0
import PackageDescription

let package = Package(
    name: "Dealer",
    products: .template(name: "loo"),
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2")

    ],
    targets: .template(
        name: "loo",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SystemPackage", package: "swift-system")

        ],
        templateInitializationOptions: .packageInit(
            templateType: .executable,
            templatePermissions: [
                .allowNetworkConnections(scope: .local(ports: [1200]), reason: "why not")
            ],
            description: "A template that generates a starter executable package"
        )
    )
)

