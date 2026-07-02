// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "package-registry-example",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "RegistryExample",
            targets: ["RegistryExample"]
        ),
        .executable(
            name: "PackageRegistryServer",
            targets: ["PackageRegistryServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "RegistryExample",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "PackageRegistryServer",
            dependencies: ["RegistryExample"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "RegistryExampleTests",
            dependencies: [
                "RegistryExample",
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6]
)
